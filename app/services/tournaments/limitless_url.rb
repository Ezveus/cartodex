# Read which of the three Limitless pages an admin pasted into the standings-import screen, and the
# values a run is addressed by.
#
# It only *extracts*. Each value is still narrowed by Admin::StandingsImportsController's own
# guards before anything is fetched, and those guards are what say why a value cannot go into a URL.
# What this refuses is a page the import does not read. Each refusal below was measured on
# 2026-10-03, and each one stops a run from importing something other than what the admin saw:
#
#   * a paper page carrying any query parameter. The page has six filters — variant, time, region,
#     division, format, type — and each lands in the URL only once it is picked; the unfiltered
#     page has none. Tournaments::LimitlessResults reads the whole deck, so a filter dropped here is
#     a wider import than the page: ?division=jr is 134 KB against the whole deck's 3.12 MB,
#     ?region=eu 940 KB, ?variant=3 1.58 MB;
#   * a paper deck's overview page (limitlesstcg.com/decks/<id>, without /results). It names the
#     same deck, but shows 15 "Latest results" where the run writes the whole history: 56 KB and
#     15 lists for deck 284, against 3.12 MB and 4593 lists on its /results page. An event's sheet
#     links every deck to that overview, so it is the address an admin is most likely to paste;
#   * an online page missing `format`, `rotation` or `set`, or carrying anything else — the bare
#     page serves Limitless's default, which follows the newest set, and `set` anchors every row to
#     a Standard pool;
#   * an online page in a format other than ONLINE_FORMAT, which the job fetches whatever the URL
#     says.
#
# An event's query string is not read: the run reads every division of the event whichever page
# was pasted, and the screen says so.
class Tournaments::LimitlessUrl < ApplicationService
  class ParseError < StandardError; end

  Parsed = Data.define(:source, :deck_id, :tournament_id, :slug, :rotation, :set) do
    def initialize(source:, deck_id: nil, tournament_id: nil, slug: nil, rotation: nil, set: nil) = super
  end

  PAPER_HOST = "limitlesstcg.com".freeze
  ONLINE_HOST = "play.limitlesstcg.com".freeze
  ONLINE_PARAMS = %w[format rotation set].freeze

  # One trailing segment on an event: its division pages (JR, SR) and its decklists, statistics and
  # cards pages all belong to the same event, and a run reads every division whichever was pasted.
  PAPER_PATH_RE = %r{\A/decks/(\d+)(/results)?/?\z}
  EVENT_PATH_RE = %r{\A/tournaments/(\d+)(?:/[A-Za-z]+)?/?\z}
  ONLINE_PATH_RE = %r{\A/decks/([^/]+)/?\z}
  SCHEME_RE = %r{\A[a-z][a-z0-9+.-]*://}i

  UNKNOWN = "Paste the address of one of the three Limitless pages this reads: " \
    "limitlesstcg.com/decks/<id>/results, " \
    "play.limitlesstcg.com/decks/<slug>?format=standard&rotation=<year>&set=<code>, or " \
    "limitlesstcg.com/tournaments/<id>.".freeze

  def initialize(text)
    # squish rather than strip: an address copied out of a web page carries U+00A0, which strip
    # leaves in place and URI.parse refuses. A missing scheme is supplied because the screen itself
    # prints every address without one, and an admin who types what it shows must not be refused.
    text = text.to_s.squish
    @text = text.empty? || SCHEME_RE.match?(text) ? text : "https://#{text}"
  end

  def call
    uri = parse_uri
    case uri.host.downcase.delete_prefix("www.")
    when PAPER_HOST then paper_or_event(uri)
    when ONLINE_HOST then online(uri)
    else raise ParseError, UNKNOWN
    end
  end

  private

  def parse_uri
    uri = URI.parse(@text)
    raise ParseError, UNKNOWN unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri
  rescue URI::InvalidURIError
    raise ParseError, UNKNOWN
  end

  # Three hand-made shapes no copied Limitless address carries, each of which was a 400 or a 500
  # rather than a sentence: a malformed escape (`x=%`) raises out of Rack, an escape decoding to
  # invalid UTF-8 (`set=%FF`) raises from the first regex that reads it, and a repeated parameter
  # comes back as an Array that every message here would print as `["standard", "standard"]`.
  def query(uri)
    params = Rack::Utils.parse_query(uri.query.to_s)
    valid = params.all? { |key, value| value.is_a?(String) && key.valid_encoding? && value.valid_encoding? }
    raise ParseError, UNKNOWN unless valid

    params
  rescue Rack::QueryParser::InvalidParameterError, Rack::QueryParser::ParameterTypeError
    raise ParseError, UNKNOWN
  end

  def paper_or_event(uri)
    if (match = EVENT_PATH_RE.match(uri.path))
      return Parsed.new(source: Tournaments::LimitlessImportJob::EVENT_SOURCE, tournament_id: match[1])
    end

    match = PAPER_PATH_RE.match(uri.path)
    raise ParseError, UNKNOWN unless match

    filters = query(uri).keys
    if filters.any?
      raise ParseError, "That page of Limitless deck #{match[1]} is filtered (#{filters.join(", ")}), " \
        "and this import reads the deck's whole tournament history — it would write more rows " \
        "than that page shows. Paste limitlesstcg.com/decks/#{match[1]}/results with no filter."
    end

    unless match[2]
      raise ParseError, "That is the overview of Limitless deck #{match[1]}, which shows only its " \
        "latest results, and this import reads the deck's whole tournament history — it would " \
        "write more rows than that page shows. Paste limitlesstcg.com/decks/#{match[1]}/results."
    end

    Parsed.new(source: "paper", deck_id: match[1])
  end

  def online(uri)
    match = ONLINE_PATH_RE.match(uri.path)
    raise ParseError, UNKNOWN unless match

    params = query(uri)
    extra = params.keys - ONLINE_PARAMS
    if extra.any?
      raise ParseError, "The leaderboard URL also carries #{extra.join(", ")}, which this import " \
        "does not read: it fetches the PTCG leaderboard by format, rotation and set alone, and a " \
        "Pocket leaderboard is the one that carries game=POCKET."
    end

    missing = ONLINE_PARAMS.reject { |name| params[name].present? }
    if missing.any?
      raise ParseError, "The leaderboard URL has no #{missing.to_sentence}. Pick the format, " \
        "rotation and set on Limitless and paste the address it shows: without them Limitless " \
        "serves its current default, and the set decides which Standard pool every row is filed under."
    end

    format = params["format"]
    unless format == Tournaments::LimitlessImportJob::ONLINE_FORMAT
      raise ParseError, "That leaderboard is #{format}, and this import only reads " \
        "#{Tournaments::LimitlessImportJob::ONLINE_FORMAT} ones."
    end

    Parsed.new(source: Tournaments::LimitlessImportJob::ONLINE_SOURCE, slug: match[1],
      rotation: params["rotation"], set: params["set"])
  end
end
