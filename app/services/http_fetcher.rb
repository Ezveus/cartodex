require "net/http"

class HttpFetcher < ApplicationService
  class FetchError < StandardError; end

  # Every fetch this app makes is a scrape of, or a proxy to, somebody else's site. Saying who we
  # are is the minimum courtesy that turns a block into a conversation, and it matters more now
  # that one admin action can ask Limitless for hundreds of pages in a row.
  USER_AGENT = "Cartodex/1.0 (+https://cartodex.ezveus.eu)".freeze

  # Net::HTTP defaults both of these to 60 seconds, which is far longer than anything here should
  # take — a card page answers in well under a second — and long enough that a hung remote holds a
  # Puma thread (there are five) or a job worker for a full minute. `read_timeout` bounds one read
  # operation rather than the whole response, so a large page is not at risk: the 1.1 MB Limitless
  # results page arrives well inside it.
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 30

  # A caller that would rather fail fast than wait may say so. Og::Renderer does: it makes two
  # serial fetches inside one web request, so the defaults above bound *it* at 2 x (10 + 30) — and
  # a host that accepts a connection and then never answers was measured holding one Puma thread
  # for 120.4 s, with the request still succeeding (degraded to the artless banner) so that nothing
  # surfaced it. A per-IP request budget cannot bound that, because it counts requests rather than
  # thread-seconds.
  def initialize(url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    @url = url
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @uri = URI.parse(url)
  rescue URI::InvalidURIError => e
    raise FetchError, "#{url.inspect} is not a URL (#{e.message})"
  end

  def call
    # A URI that is not HTTP(S) has no hostname to open, and interpolating an unvalidated segment
    # into a URL is how a fetch ends up pointed somewhere it was never meant to go. Callers narrow
    # what they interpolate; this is the backstop that keeps anything else from reaching Net::HTTP.
    raise FetchError, "#{@url.inspect} is not an HTTP URL" unless @uri.is_a?(URI::HTTP)

    response = perform_request
    raise FetchError, "HTTP #{response.code} for #{@uri}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  private

  def perform_request
    Net::HTTP.start(
      @uri.hostname, @uri.port,
      use_ssl: @uri.scheme == "https",
      open_timeout: @open_timeout,
      read_timeout: @read_timeout
    ) { |http| http.request(Net::HTTP::Get.new(@uri, "User-Agent" => USER_AGENT)) }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    # Rescued into FetchError rather than left to propagate, because every caller already handles
    # that one class — CardsController#image rescues it to answer 502 rather than 500, and the
    # import jobs turn it into a failed Import — and a timeout is the same kind of event as a 503.
    raise FetchError, "#{e.class} for #{@uri}"
  rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
    raise FetchError, "#{e.class} for #{@uri}: #{e.message}"
  end
end
