# Dashboard spotlight search. Answers a Turbo Frame request on every keystroke, so the response
# carries the frame and nothing else — no layout, no navbar.
class SearchController < ApplicationController
  include Searchable
  include PubliclyReachable

  publicly_reachable :show

  layout false

  # One LIKE '%…%' over the whole card catalog per keystroke, plus one over the shared decks.
  # MIN_QUERY_LENGTH and NameNormalizable::MAX_QUERY_LENGTH bound the pattern; nothing bounded
  # the rate until this action became reachable without a session.
  RATE_LIMIT_TO = 120
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "search", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :show

  def show
    authorize :dashboard, :show?
    @results = search_results
  end
end
