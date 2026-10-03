# Read which of the three Limitless pages an admin pasted into the standings-import screen, and the
# values a run is addressed by.
#
# It only *extracts*. Each value is still narrowed by Admin::StandingsImportsController's own
# guards before anything is fetched, and those guards are what say why a value cannot go into a URL.
# What this refuses is a page the import does not read. Three of those refusals were measured on
# 2026-10-03, and each one stops a run from importing something other than what the admin saw:
#
#   * a paper page carrying `?variant=` — decks/284/results?variant=3 is 1.58 MB against the whole
#     deck's 3.12 MB, and Tournaments::LimitlessResults reads the whole deck;
#   * an online page missing `format`, `rotation` or `set` — the bare page serves Limitless's
#     default, which follows the newest set, and `set` anchors every row to a Standard pool;
#   * an online page in a format other than ONLINE_FORMAT, which the job fetches whatever the URL
#     says.
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
  PAPER_PATH_RE = %r{\A/decks/(\d+)(?:/results)?/?\z}
  EVENT_PATH_RE = %r{\A/tournaments/(\d+)(?:/[A-Za-z]+)?/?\z}
  ONLINE_PATH_RE = %r{\A/decks/([^/]+)/?\z}

  UNKNOWN = "Paste the address of one of the three Limitless pages this reads: " \
    "limitlesstcg.com/decks/<id>/results, " \
    "play.limitlesstcg.com/decks/<slug>?format=standard&rotation=<year>&set=<code>, or " \
    "limitlesstcg.com/tournaments/<id>.".freeze

  def initialize(text)
    # squish rather than strip: an address copied out of a web page carries U+00A0, which strip
    # leaves in place and URI.parse refuses.
    @text = text.to_s.squish
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

  def query(uri) = Rack::Utils.parse_query(uri.query.to_s)

  def paper_or_event(uri)
    if (match = EVENT_PATH_RE.match(uri.path))
      return Parsed.new(source: Tournaments::LimitlessImportJob::EVENT_SOURCE, tournament_id: match[1])
    end

    match = PAPER_PATH_RE.match(uri.path)
    raise ParseError, UNKNOWN unless match

    if query(uri).key?("variant")
      raise ParseError, "That is one variant of Limitless deck #{match[1]}, and this import reads the " \
        "deck's whole tournament history — it would write more rows than that page shows. Paste " \
        "limitlesstcg.com/decks/#{match[1]}/results without ?variant."
    end

    Parsed.new(source: "paper", deck_id: match[1])
  end

  def online(uri)
    match = ONLINE_PATH_RE.match(uri.path)
    raise ParseError, UNKNOWN unless match

    params = query(uri)
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
