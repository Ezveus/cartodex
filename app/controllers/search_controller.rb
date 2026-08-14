# Dashboard spotlight search. Answers a Turbo Frame request on every keystroke, so the response
# carries the frame and nothing else — no layout, no navbar.
class SearchController < ApplicationController
  include Searchable

  layout false

  def show
    @results = search_results
  end
end
