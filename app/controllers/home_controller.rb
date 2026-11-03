class HomeController < ApplicationController
  # Three-pane guided search page (chat, ranked school cards, map), rendered
  # from the sample fixture in db/sample/results.json. Next step: feed it the
  # agent's turns from GuidedSearch::Turn, keeping the SearchResult shape
  # described in docs/card_contract.md.
  def show
    @search = SearchResult.sample
  end
end
