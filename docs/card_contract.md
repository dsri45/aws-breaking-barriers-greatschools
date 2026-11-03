# Card contract: what the agent returns for the UI

The frontend renders whatever the agent's `present_results` tool returns, in the
shape of [`db/sample/results.json`](../db/sample/results.json). Build the agent
to emit this shape and the page needs no changes.

## Top level

| Field | Type | Notes |
| --- | --- | --- |
| `query` | string | The parent's question, shown in the search box |
| `criteria[]` | `{key, label, importance}` | Chips. `importance`: `require` (MUST), `prefer` (NICE), `avoid` |
| `messages[]` | see below | Chat transcript, rendered top to bottom |
| `results[]` | see below | Ranked school cards, best first. The first one is selected on the map |
| `nearby_unmatched[]` | `{name, summary_rating, latlon}` | Muted pins for context |

## `messages[]`

| `role` | Fields |
| --- | --- |
| `user` | `text` |
| `assistant` | `text`, optional `highlights[]` (exact phrases from `text` to highlight green) |
| `question` | `text`, `hint`, `options[]`, optional `selected` (from `ask_clarifying_question`) |
| `status` | `steps[]` of `{state: "done" or "flag", text}` (what the agent checked) |

## `results[]`

| Field | Type | Notes |
| --- | --- | --- |
| `school_id` | string | |
| `rank_label` | string | e.g. "Best STEM match" |
| `name`, `entity_type`, `grades` | string | `entity_type`: public, charter, private |
| `distance_mi` | number | |
| `summary_rating` | integer or null | null renders "No rating yet", never a low score |
| `avg_review_rating`, `review_count` | number | |
| `review_topic` | string | From `sentiment_stats`, e.g. "Teachers: mostly positive" |
| `why` | string | The agent's one-line "Good fit if..." |
| `latlon` | string | `"lat, lon"`, same as the GreatSchools sample data |
| `saved` | boolean | Heart state |
| `criteria[]` | `{key, label, status, evidence, as_of}` | One row per criterion. `status`: `confirmed`, `partial`, `needs_attention`, `missing`. `as_of` is an ISO date or null; data older than 12 months gets a "From YYYY" badge |

Evidence `status` should be computed in Ruby from the school's fields, not by the
model; the model writes `why`, `rank_label` and the chat text.
