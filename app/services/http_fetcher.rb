require "net/http"

class HttpFetcher < ApplicationService
  class FetchError < StandardError; end

  def initialize(url)
    @uri = URI.parse(url)
  end

  def call
    response = Net::HTTP.get_response(@uri)

    raise FetchError, "HTTP #{response.code} for #{@uri}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end
end
