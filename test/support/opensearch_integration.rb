module OpenSearchIntegration
  # Include in tests that need a live OpenSearch node. If OPENSEARCH_URL is
  # unset or the node is unreachable, the test is skipped (not failed) so the
  # default suite runs without Docker.
  #
  # Set OPENSEARCH_URL=http://localhost:9200 (and EMBEDDINGS_MODE=stub) to run.
  def self.available?
    return @available unless @available.nil?

    @available =
      begin
        ENV["OPENSEARCH_URL"].present? &&
          GuidedSearch::OpenSearch.new.request("GET", "/_cluster/health").present?
      rescue StandardError
        false
      end
  end

  # Recreate indexes and load the sample data once per suite run.
  def self.load_once!
    return if @loaded

    GuidedSearch::Indexer.new.recreate_all
    GuidedSearch::DataLoader.new(embeddings: GuidedSearch::Embeddings.new(mode: "stub")).load_all
    @loaded = true
  end

  module Helpers
    def skip_unless_opensearch
      skip "OpenSearch not reachable (set OPENSEARCH_URL to a local node)" unless OpenSearchIntegration.available?
      OpenSearchIntegration.load_once!
    end
  end
end
