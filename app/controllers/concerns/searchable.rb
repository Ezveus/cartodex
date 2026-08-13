# Shared reading of the `q` search param. /search, /decks and /tournaments all read the query
# through here so they can't drift on the param name or on trimming.
module Searchable
  extend ActiveSupport::Concern

  private

  # The `q` param, trimmed; "" when absent.
  def search_query
    @search_query ||= params[:q].to_s.strip
  end

  # Grouped decks/cards/tournaments matches for the current user. The short-query cut-off is the
  # service's (Search::Global::MIN_QUERY_LENGTH), so the index pages above can filter from the
  # first character while the spotlight waits for two.
  def search_results(limit: Search::Global::DEFAULT_LIMIT)
    Search::Global.call(user: current_user, query: search_query, limit: limit)
  end
end
