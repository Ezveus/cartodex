require "nokogiri"

# Read every printing carrying one Limitless search label, in one request.
#
# `limitlesstcg.com/cards?q=<token>&show=all` answers with the whole result set: measured on
# 2026-09-05, is:ace 46 links for an announced 46 in 25 KB, is:tera 151 for 151, and the largest
# plausible label, is:ex, 986 for 986 in 234 KB. So there is no pagination to write and no page cap
# to tune, and the count the page announces is free to be an integrity check rather than a
# stopping condition.
#
# It returns printings, not cards. Resolving them against the catalogue — and deciding what to do
# about the ones it does not hold — is CardLabels::Importer's job.
class CardLabels::LimitlessSearch < ApplicationService
  class ParseError < StandardError; end

  BASE_URL = "https://limitlesstcg.com".freeze

  # What a Limitless search token may contain. Narrow because it is interpolated into a URL that is
  # then fetched: `is:ace`, `is:fusion+aa`, `is:prism,tt`, `-is:gx`. A leading `-` is accepted
  # deliberately, and it is not a free negation: `-is:gx` searches the *complement* of the label
  # — thousands of printings rather than a few dozen — and the importer's "never deletes" rule
  # (decision 4) means a run like that cannot be walked back once written, short of destroying the
  # label itself (which does cascade its assignments). No validation stops an admin typing one in;
  # this is the one place that says so before a run does.
  TOKEN_RE = /\A-?[a-z]+:[a-z0-9,+\-]+\z/

  CARD_HREF_RE = %r{\A/cards/([A-Za-z0-9]+)/([A-Za-z0-9]+)\z}
  # "46 cards found where …" — and "1 card found" for a label with one printing.
  COUNT_RE = /\A\s*([\d,]+)\s+cards?\s+found/

  Printing = Struct.new(:set_code, :number, keyword_init: true)

  Result = Struct.new(:printings, :announced_count, keyword_init: true) do
    # False when the page said one thing and the grid held another. Not an error here: the caller
    # writes what it read and says so in the receipt, which is more useful than refusing a run
    # over a count it cannot check any other way.
    def complete? = announced_count.nil? || announced_count == printings.size
  end

  def initialize(token)
    @token = token.to_s
    return if @token.match?(TOKEN_RE)

    raise ArgumentError, "#{@token.inspect} is not a Limitless search token"
  end

  def call
    doc = Nokogiri::HTML(HttpFetcher.call(url))
    grid = doc.at_css(".card-search-grid")
    raise ParseError, "no card grid at #{url} — the page layout may have changed" if grid.nil?

    printings = grid.css("a[href]").filter_map { |link| printing_for(link["href"]) }.uniq
    raise ParseError, "no cards at #{url}" if printings.empty?

    Result.new(printings: printings, announced_count: announced_count(doc))
  end

  def url = "#{BASE_URL}/cards?#{{ q: @token, show: "all" }.to_query}"

  private

  # Matched against the whole href rather than searched for: the page carries other links under
  # /cards (the syntax page, the advanced search), and "any link starting with /cards" would read
  # them as printings.
  def printing_for(href)
    match = CARD_HREF_RE.match(href.to_s) or return nil

    Printing.new(set_code: match[1], number: match[2])
  end

  def announced_count(doc)
    summary = doc.at_css(".search-summary")&.text or return nil
    match = COUNT_RE.match(summary) or return nil

    match[1].delete(",").to_i
  end
end
