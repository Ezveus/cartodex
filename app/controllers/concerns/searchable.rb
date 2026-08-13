# Shared reading of the `q` search param. /search, /decks and /tournaments all read the query
# through here so they can't drift on the param name or on trimming.
module Searchable
  extend ActiveSupport::Concern

  private

  # The `q` param, trimmed; "" when absent.
  def search_query
    @search_query ||= params[:q].to_s.strip
  end
end
