# Search & data layer

Two OpenSearch indexes (`schools`, `programs`) loaded from the GreatSchools
sample JSON, served through hybrid keyword + vector search. Evidence is scored
in Ruby from each school's fields (see [card_contract.md](card_contract.md)); the
agent only writes `why`, `rank_label`, and chat text.

All classes live under `GuidedSearch::` and reuse the existing
`GuidedSearch::OpenSearch` transport (raw REST + SigV4).

## Components

| Class | Role |
| --- | --- |
| `GuidedSearch::OpenSearch` | REST transport. Managed = HTTPS + SigV4; an `http://` `OPENSEARCH_URL` enables an unsigned local-dev path. Adds an `ndjson:` option for `_bulk`. |
| `GuidedSearch::Embeddings` | Titan Text Embeddings V2 (1024-dim) via `invoke_model`, or a deterministic `stub` mode for dev/tests. |
| `GuidedSearch::Indexer` | Idempotent create/drop of indexes from `config/opensearch/*.json`. |
| `GuidedSearch::DataLoader` | Reads `db/seeds/*.json`, converts `latlon` → geo_point, embeds, bulk-indexes by the string `id`. Absent fields are preserved. |
| `GuidedSearch::SchoolSearch` / `ProgramSearch` | Hybrid BM25 + k-NN legs, blended in Ruby by `HybridRanker`. |
| `GuidedSearch::HybridRanker` | Min-max normalizes each leg and blends: `alpha*bm25 + (1-alpha)*knn`. |
| `GuidedSearch::EvidenceScorer` | Per-criterion `{status, evidence, as_of}` from school fields. Null rating → `missing` ("No rating published"), never a low score. |
| `GuidedSearch::OpenSearchRetriever` | Drop-in for `DemoSearch`: `call(preferences:)` → ranked cards in the `db/sample/results.json` shape. |

## Environment

See `.env.example`. Key vars: `OPENSEARCH_URL`, `AWS_REGION`, `EMBEDDINGS_MODE`
(`bedrock` or `stub`), `GUIDED_SEARCH_RETRIEVER`.

## Local development

```bash
# 1. Start a local OpenSearch node (security disabled, dev only)
docker run --rm -p 9200:9200 \
  -e discovery.type=single-node \
  -e plugins.security.disabled=true \
  -e OPENSEARCH_INITIAL_ADMIN_PASSWORD=Dev_Only_Passw0rd! \
  opensearchproject/opensearch:2.17.1

# 2. Create indexes and load the sample data (stub embeddings, no AWS needed)
export OPENSEARCH_URL=http://localhost:9200 EMBEDDINGS_MODE=stub
bin/rails data:reload          # drop + recreate + load 25 schools, 25 programs
bin/rails opensearch:status    # show counts
```

Rake tasks: `opensearch:create_indexes`, `opensearch:drop_indexes`,
`opensearch:recreate_indexes`, `opensearch:status`, `data:load`, `data:reload`.

## Wiring the agent to real search

`GuidedSearch::Turn` picks its retriever from `GUIDED_SEARCH_RETRIEVER`
(default `GuidedSearch::DemoSearch`). Point it at the real one:

```bash
GUIDED_SEARCH_RETRIEVER=GuidedSearch::OpenSearchRetriever
```

It expects `preferences` shaped like:

```ruby
{
  "query"    => "middle school in Woodstock with STEM",   # free-text wish
  "criteria" => [{ "key" => "stem", "label" => "STEM", "importance" => "require" }],
  "filters"  => { "state" => "FL", "level_codes" => "m", "entity_type" => "public" },
  "geo"      => { "lat" => 30.33, "lon" => -81.65, "radius_km" => 25 },
  "size"     => 5
}
```

and returns an array of card hashes (`school_id`, `grades`, `distance_mi`,
`summary_rating`, `review_topic`, `criteria[]` evidence rows, …). The agent
fills `why` and `rank_label`.

## Tests

Unit tests (no OpenSearch) run in the default suite. Integration tests under
`test/integration/guided_search_opensearch_test.rb` skip unless
`OPENSEARCH_URL` is set:

```bash
# unit only (default)
bin/rails test

# including live OpenSearch integration
OPENSEARCH_URL=http://localhost:9200 EMBEDDINGS_MODE=stub bin/rails test
```

## Managed domain

Set `OPENSEARCH_URL` to the HTTPS domain endpoint and provide AWS credentials
(env, `~/.aws`, or the instance/task role). The same rake tasks and search code
run unchanged; requests are SigV4-signed automatically. Set
`EMBEDDINGS_MODE=bedrock` for real Titan embeddings.
