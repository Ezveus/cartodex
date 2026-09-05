# Decide what a Limitless results page would become, without writing any of it.
#
# This is the whole point of the preview: 1569 rows is far more than anyone means to import, and a
# silently partial extraction is invisible unless there is a count to compare against. So every
# decision that could write something wrong into the public catalog — which event a row belongs to,
# which tier and format that event has, whether it can be created at all, whether a standing
# already exists — is made here, named, and rendered for an admin to look at before anything runs.
#
# It reads the database but never writes to it. Tournaments::StandingsImporter takes the plan and
# writes it.
class Tournaments::StandingsImportPlan < ApplicationService
  # The ceiling on one run, as a keyword rather than a constant so a test can prove the refusal
  # with two rows instead of a 300-row HTML fixture. A run that fetched every list on the page
  # would be thousands of requests to somebody else's site and is never what an admin meant.
  DEFAULT_MAX_ROWS = 300

  # `tournaments.tier` defaults to "regional" in the schema, so leaving it alone files a World
  # Championship as a Regional — which then feeds Tournament::CP_REFERENCE and offers a claimant
  # 350 championship points instead of 600. Guessed from the name, in order, and shown per event in
  # the preview so a wrong guess is caught before it is public rather than after.
  TIER_PATTERNS = [
    [ /world championship/i, "worlds" ],
    [ /\b(?:NAIC|EUIC|LAIC|OCIC)\b/i, "international" ],
    [ /international championship/i, "international" ],
    [ /\bregional\b/i, "regional" ],
    [ /special event/i, "regional" ],
    [ /league cup/i, "league_cup" ],
    [ /league challenge/i, "league_challenge" ]
  ].freeze
  DEFAULT_TIER = "other".freeze

  # Limitless's own format labels, mapped to (format, other_format_name). The "-jp" pair is why
  # this is a table and not `Tournament.formats.key?`: "standard-jp" is the Japanese card pool, and
  # writing it as `standard` would force a western StandardPool onto a Japanese event — the same
  # lie a missing pool is refused for, in the other direction. As `other` it needs no pool and
  # records what is actually true. (The decklists themselves are safe: Limitless normalises even a
  # Champions League list to English set codes, verified on list 27923.)
  FORMATS = {
    "standard" => [ "standard", nil ],
    "expanded" => [ "expanded", nil ],
    "standard-jp" => [ "other", "Standard (JP)" ],
    "expanded-jp" => [ "other", "Expanded (JP)" ]
  }.freeze

  # A window, not an exact date, because Limitless records the day an event *starts* and a member
  # cataloguing a three-day International may well have typed the day they played. Two rows whose
  # names differ by a city ("NAIC 2026" against "NAIC 2026, New Orleans") are a duplicate the
  # UNIQUE key on (name_normalized, date) cannot see, and one of them will become undeletable the
  # moment somebody records a participation at it.
  SIMILAR_DATE_WINDOW = 3

  RowPlan = Struct.new(:row, :status, :reason, :standing, :other_division, keyword_init: true) do
    def importable? = status == :create || status == :enrich
  end

  EventPlan = Struct.new(
    :name, :date, :external_key, :tier, :format, :other_format_name, :standard_pool, :online,
    :participant_count, :tournament, :blocked_reason, :similar_tournaments, :rows,
    keyword_init: true
  ) do
    def blocked? = blocked_reason.present?
    def importable_rows = rows.select(&:importable?)
    def count(status) = rows.count { |row| row.status == status }
  end

  Plan = Struct.new(:events, :max_rows, keyword_init: true) do
    def importable_rows = events.flat_map(&:importable_rows)
    def total_rows = events.sum { |event| event.rows.size }
    def count(status) = events.sum { |event| event.count(status) }
    def over_limit? = importable_rows.size > max_rows
  end

  # `online` and `standard_pool` travel together and only the online source passes either. They are
  # a classification the *caller* knows and the rows cannot say: play.limitlesstcg.com's leaderboard
  # names its card pool in the URL's `set` parameter, and its event names are arbitrary strings that
  # must never be read for a tier. Their defaults are exactly what the paper source has always done.
  def initialize(rows:, event_filters: [], limit_per_event: nil, max_rows: DEFAULT_MAX_ROWS,
    online: false, standard_pool: nil)
    @rows = rows
    @event_filters = Array(event_filters).map { |filter| filter.to_s.strip.downcase }.reject(&:empty?)
    @limit_per_event = limit_per_event.presence&.to_i
    @max_rows = max_rows
    @online = online
    @standard_pool = standard_pool
  end

  def call
    groups = grouped_rows.values
    @catalogued = load_catalogued(groups.flatten)
    @standings = load_standings

    events = groups.map { |rows| build_event(rows) }
    Plan.new(events: events.sort_by { |event| event.date }.reverse, max_rows: @max_rows)
  end

  private

  # Two queries for the whole plan rather than three per event. The unfiltered page really does
  # hold 116 events, and resolving each one on its own turned a preview into 230-odd queries in a
  # single web request — most of them spent before `over_limit?` had a chance to refuse the plan.
  # `with_standard_pool` because the plan renders each pool by name, which reads both of its bounds.
  #
  # A paper run reads `Tournament.catalogued` and an online run reads the other half, so neither
  # ever sees the other's events. Without the split every *paper* preview would list online weeklies
  # as "similar tournaments" noise — #similar_tournaments is an O(events x catalogued) Ruby scan
  # over this set, and this source fills the table with twenty events per archetype per pool, so the
  # scan grows without bound as it is used. An online run needs its own half for the opposite
  # reason: recognising the events it created last time is the whole of the idempotence property —
  # a re-import that could not find them would plan every surviving row as :create and lose to the
  # UNIQUE key row by row instead of skipping.
  def load_catalogued(rows)
    return [] if rows.empty?

    dates = rows.map(&:event_date)
    scope = @online ? Tournament.where(online: true) : Tournament.catalogued
    scope.with_standard_pool
      .where(date: (dates.min - SIMILAR_DATE_WINDOW)..(dates.max + SIMILAR_DATE_WINDOW)).to_a
  end

  def load_standings
    ids = @catalogued.map(&:id)
    return {} if ids.empty?

    TournamentStanding.where(tournament_id: ids).group_by(&:tournament_id)
  end

  # An event is a name and a date for the paper source, and its own Limitless id for the online
  # one. Grouping an online run on the name and date is what merged two genuinely different
  # tournaments into a single event: online names are arbitrary and repeat weekly
  # ("Pumpkaweekly", "CrownOfSpain #4"), so one day really does hold two of them — after which
  # the merged event takes its attendance from whichever row came first and refuses the other
  # event's rows for a placement above a field size that was never theirs.
  #
  # The id *replaces* the pair rather than joining it: an id is an identity, and a key holding
  # both would split one event again the moment two of its rows spelled its name differently. A
  # source that publishes no id per row keys on the pair, which is exactly what the paper source
  # has always done.
  def grouped_rows
    filtered = @rows
    filtered = filtered.select { |row| @event_filters.any? { |f| row.event_name.downcase.include?(f) } } if
      @event_filters.any?

    filtered.group_by { |row| external_key_of(row) || [ row.event_name, row.event_date ] }
  end

  # Only an online run has one. Asking the row rather than branching on @online for the same
  # reason #participant_count does: the two sources share a contract of eight fields and the
  # online one adds to it.
  def external_key_of(row)
    return unless @online

    row.event_key.presence if row.respond_to?(:event_key)
  end

  # The name and the date are read off the group's first row rather than off its key, because for
  # an online run the key is the id alone. Which row that is decides nothing: they are the rows of
  # one event, and the plan renders the name only.
  def build_event(rows)
    name = rows.first.event_name
    date = rows.first.event_date
    external_key = external_key_of(rows.first)
    normalized = name.squish.downcase
    tournament = find_catalogued(normalized, date, external_key)
    derived = classification(rows, date)
    # Taken whole from an existing event, or derived whole — never field by field. Mixing them
    # produces records like format "standard" carrying an other_format_name, which is meaningless
    # even where a callback later drops it.
    settled = tournament ? classification_of(tournament) : derived

    event = EventPlan.new(
      name: name, date: date, external_key: external_key, tournament: tournament,
      tier: tournament&.tier || tier_for(name),
      online: @online, participant_count: participant_count(rows),
      **settled,
      blocked_reason: blocked_reason(rows: rows, derived: derived, tournament: tournament, date: date),
      similar_tournaments: tournament ? [] : similar_tournaments(normalized, date),
      rows: []
    )
    event.rows = build_rows(event, capped(rows))
    event
  end

  # An online event is looked up by the id the source gave it and never by its name — the run
  # that created it wrote that id, so this is what makes a re-import find its own events and skip
  # them instead of planning every row :create and losing to the UNIQUE key one at a time.
  # @catalogued is already partitioned by venue, so neither lookup can ever reach the other's
  # half.
  def find_catalogued(normalized, date, external_key)
    return @catalogued.find { |candidate| candidate.external_key == external_key } if external_key

    @catalogued.find { |candidate| candidate.name_normalized == normalized && candidate.date == date }
  end

  def classification(rows, date)
    format, other_format_name = FORMATS.fetch(dominant_format(rows), [ nil, nil ])
    { format: format, other_format_name: other_format_name,
      standard_pool: (standard_pool_for(date) if format == "standard") }
  end

  # StandardPool.at reads `legal_on` — the date Play! Pokemon considers a pool legal, about two
  # weeks after the cards ship. Online play follows the *release*, so the leaderboard's own `set`
  # parameter is the anchor and the date says nothing about it. Measured: 3 of the 20 rows of one
  # PBL leaderboard (2026-07-28/29/30) predate TEF-PBL's legal_on of 2026-07-31, so anchoring them
  # by date files them under TEF-CRI, in a sample whose other lists could not legally hold their
  # cards.
  def standard_pool_for(date)
    @online ? @standard_pool : StandardPool.at(date)
  end

  # The leaderboard prints the field size on every row ("1st of 259"), and the rows of one event
  # agree on it because it is the event's own attendance — so the first that carries one answers
  # for the event. The paper source publishes none, which is why every event imported from it has
  # nil participant counts, and why this asks the row rather than assuming the field exists.
  def participant_count(rows)
    rows.filter_map { |row| row.attendance if row.respond_to?(:attendance) }.first
  end

  def classification_of(tournament)
    { format: tournament.format, other_format_name: tournament.other_format_name,
      standard_pool: tournament.standard_pool }
  end

  # The format icon is on the row, not the heading, so an event's format is whatever its rows
  # agree on. They do agree — no event on the measured page mixes two — but taking the most common
  # rather than the first means a stray icon cannot decide an event's format on its own.
  def dominant_format(rows)
    rows.map(&:format).compact.tally.max_by { |_format, count| count }&.first
  end

  # Forced, never guessed, for an online event. TIER_PATTERNS reads a name, and online event names
  # are arbitrary — "TOURNAMENT OF DOOM! WORLDS LCQ!", "CrownOfSpain #4". All twenty measured names
  # fall through to `other` today, but one holding "Regional" would be filed as a Regional and
  # Tournament::CP_REFERENCE would then offer championship points for an online event.
  def tier_for(name)
    return DEFAULT_TIER if @online

    TIER_PATTERNS.find { |pattern, _tier| pattern.match?(name) }&.last || DEFAULT_TIER
  end

  # Keywords rather than positions: this took five of them, two of which were a Tournament and a
  # StandardPool, and swapping those two would have been silent.
  def blocked_reason(rows:, derived:, tournament:, date:)
    return "Limitless reports the format as #{dominant_format(rows).inspect}, which cartodex has no value for" if
      derived[:format].nil?
    # Only for an event this run would have to create: an existing Standard tournament already has
    # a pool, and its own form is where that gets corrected.
    return if tournament
    return unless derived[:format] == "standard"
    return if derived[:standard_pool]
    # An online run is anchored by the leaderboard's `set`, not by the date, so naming the date
    # would send the admin to look for a pool that covers it — which is not the thing that is
    # missing and may well already exist.
    return "no Standard pool matches this leaderboard's set — pick a set that names one, or add the pool from Admin → Standard pools, and re-run" if @online

    "no Standard pool covers #{date} — add one from Admin → Standard pools and re-run"
  end

  # Per event *and* division, not per event: a cap applied across the whole event would keep ten
  # Masters rows and drop the single Junior one, which is the row hardest to find anywhere else.
  def capped(rows)
    ordered = rows.sort_by { |row| [ row.placement || Float::INFINITY, row.player_name.to_s ] }
    return ordered if @limit_per_event.nil? || @limit_per_event <= 0

    ordered.group_by(&:division).flat_map { |_division, group| group.first(@limit_per_event) }
  end

  def build_rows(event, rows)
    existing = existing_standings(event.tournament)

    rows.map { |row| build_row(event, row, existing) }
  end

  def existing_standings(tournament)
    return {} if tournament.nil?

    (@standings[tournament.id] || []).group_by { |standing| standing.player_name_normalized }
  end

  def build_row(event, row, existing)
    return RowPlan.new(row: row, status: :blocked, reason: event.blocked_reason) if event.blocked?
    if row.division.nil?
      return RowPlan.new(row: row, status: :blocked,
        reason: "Limitless labels this event #{row.division_suffix.inspect}, which is not an age division cartodex knows")
    end

    for_player = existing[row.player_name.to_s.squish.downcase] || []
    standing = for_player.find { |candidate| candidate.division == row.division }
    # The same human, filed twice: the UNIQUE key is (event, player, division), so a row a member
    # typed under the default Masters and the Senior row this import derives from a /SR suffix
    # collide on nothing and both go public. It cannot be resolved from here — which of the two is
    # right is a fact about a person — so it is flagged for the admin instead.
    other_division = for_player.find { |candidate| candidate.division != row.division }

    RowPlan.new(row: row, standing: standing, other_division: other_division, **status_for(row, standing))
  end

  def status_for(row, standing)
    return { status: :create } if standing.nil?
    # Filling a NULL deck_id overwrites nothing, and a row naming an archetype with no list is the
    # common case — the two runs an admin actually makes (re-importing once Limitless posts the
    # lists, enriching rows a member typed) would otherwise both do nothing at all.
    return { status: :enrich } if standing.deck_id.nil? && row.list_url.present?

    { status: :skip, reason: standing.deck_id ? "already has a field list" : "no field list to add" }
  end

  def similar_tournaments(normalized, date)
    window = (date - SIMILAR_DATE_WINDOW)..(date + SIMILAR_DATE_WINDOW)

    @catalogued.select { |candidate|
      other = candidate.name_normalized.to_s
      window.cover?(candidate.date) && other != normalized &&
        (other.include?(normalized) || normalized.include?(other))
    }
  end
end
