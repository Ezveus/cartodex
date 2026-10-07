# The ⌘K spotlight's search, and the page a browser's search engine opens. Both run the very same
# search_results call; only the wrapping differs. The spotlight's form targets the results frame,
# so its request carries a Turbo-Frame header and gets the frame and nothing else — no layout, no
# navbar — on every keystroke. Any other GET of /search?q=… is somebody arriving from their
# address bar, and gets the same list inside a whole page.
class SearchController < ApplicationController
  include Searchable
  include PubliclyReachable

  publicly_reachable :show

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

    if turbo_frame_request?
      render :show, layout: false
    else
      render :page
    end
  end
end
