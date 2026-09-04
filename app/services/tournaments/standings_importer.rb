# Write a Tournaments::StandingsImportPlan: the events it says to create, the standings, and the
# field lists.
#
# It never raises for one bad row. A run touches a public catalog dozens of rows at a time, and a
# single unparseable decklist or a placement above a field size somebody typed last week is not a
# reason to abandon the other forty — so failures are collected, named, and reported. The one thing
# that does stop a run is the far side going away: five fetch failures in a row means Limitless is
# rate-limiting or down, and collecting three hundred identical refusals under a green status would
# be a lie.
class Tournaments::StandingsImporter < ApplicationService
  # A run that keeps asking after five refusals in a row is not going to get a different answer,
  # and every further request makes the block it is being given more deserved.
  CONSECUTIVE_FAILURE_LIMIT = 5

  Result = Struct.new(
    :created, :enriched, :skipped, :blocked, :standing_ids, :failures, :aborted_reason,
    keyword_init: true
  ) do
    def aborted? = aborted_reason.present?
    def failed_count = failures.size
  end

  # `pause` is injectable and zero by default so tests do not sleep, but the job passes a real one:
  # a run is hundreds of requests to somebody else's site in a tight loop, and nothing else in this
  # app asks Limitless for that much at once.
  def initialize(plan:, archetype:, user:, pause: 0.0)
    @plan = plan
    @archetype = archetype
    @user = user
    @pause = pause
    @standing_ids = []
    @failures = []
    @counts = Hash.new(0)
    @consecutive_failures = 0
  end

  def call
    @plan.events.each { |event| import_event(event) }
    result
  rescue RunAborted => e
    result(aborted_reason: e.message)
  end

  private

  class RunAborted < StandardError; end

  def result(aborted_reason: nil)
    Result.new(
      created: @counts[:create], enriched: @counts[:enrich],
      skipped: @counts[:skip], blocked: @counts[:blocked],
      standing_ids: @standing_ids, failures: @failures, aborted_reason: aborted_reason
    )
  end

  def import_event(event)
    if event.blocked?
      @counts[:blocked] += event.rows.size
      return
    end

    tournament = find_or_create_tournament(event)
    event.rows.each { |row_plan| import_row(tournament, event, row_plan) }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    # The event could not be created, so none of its rows can be: one failure, named once, rather
    # than the same message repeated per row.
    @failures << [ "#{event.name} (#{event.date})", e.message ]
    @counts[:blocked] += event.rows.size
  end

  # find_or_create_by is unusable here: `before_validation :normalize_name` recomputes
  # name_normalized from `name`, which such a call leaves nil, so the create fails validation and
  # find_or_create_by hands back an unpersisted record without raising a thing. The
  # RecordNotUnique rescue is the other half — the uniqueness *validation* is a non-atomic
  # `exists?`, and a member cataloguing this event while the run walks it wins that race.
  def find_or_create_tournament(event)
    return event.tournament if event.tournament

    Tournament.create!(
      name: event.name, date: event.date, tier: event.tier, format: event.format,
      other_format_name: event.other_format_name, standard_pool: event.standard_pool,
      created_by: @user
    )
  rescue ActiveRecord::RecordNotUnique
    Tournament.find_by!(name_normalized: event.name.squish.downcase, date: event.date)
  end

  def import_row(tournament, event, row_plan)
    case row_plan.status
    when :create then create_standing(tournament, event, row_plan)
    when :enrich then enrich_standing(event, row_plan)
    else @counts[row_plan.status] += 1
    end
  rescue StandardError => e
    # Recorded before the re-raise, so the row that finally exhausted the run's patience is named
    # in the report like the four before it rather than vanishing into the abort message.
    @failures << [ row_label(event, row_plan), e.message ]
    raise if e.is_a?(RunAborted)
  end

  def create_standing(tournament, event, row_plan)
    row = row_plan.row
    standing = build_standing(tournament, row)
    @standing_ids << standing.id
    @counts[:create] += 1
    attach_field_list(standing, event, row)
  end

  def build_standing(tournament, row)
    tournament.standings.create!(
      player_name: row.player_name, division: row.division, placement: row.placement,
      archetype: @archetype, created_by: @user
    )
  rescue ActiveRecord::RecordNotUnique
    # Lost the race against a member typing this very row. Their version is the one that stands —
    # this is a wiki — so the run reports it rather than trying to win.
    raise ActiveRecord::RecordInvalid.new(tournament.standings.new),
      "a standing for this player was created while the import was running"
  end

  # Enrichment fills a NULL deck_id and nothing else. Every other column on an existing row was
  # either typed by a member or written by an earlier run, and overwriting it is what would make
  # this import a republish instead of an import.
  def enrich_standing(event, row_plan)
    attach_field_list(row_plan.standing, event, row_plan.row)
    @counts[:enrich] += 1
  end

  # The order is what keeps an orphan from existing: Decks::Fetcher commits its own transaction, so
  # a list built before its standing is a shared, ownerless deck referenced by nothing the moment
  # the standing fails to validate — reachable on /decks/shared and deletable through no path in
  # the app. `deck` is optional on a standing, so the standing goes first and the list is attached
  # after, with the same discard guard Tournaments::StandingListImportJob already carries.
  def attach_field_list(standing, event, row)
    return if row.list_url.blank?

    text = fetch_decklist(row.list_url)
    resolve_printings(text)
    deck = ::Decks::Fetcher.call(
      text, nil, deck_name(standing, event),
      shared: true, format: event.format, standard_pool: event.standard_pool,
      other_format_name: event.other_format_name
    )

    begin
      standing.update!(deck: deck)
    rescue StandardError
      discard_orphaned_list(deck, standing.id)
      raise
    end
  end

  # Every printing is resolved *before* Decks::Fetcher opens its transaction. That transaction is a
  # SQLite BEGIN IMMEDIATE — it takes the database's single write lock at `Deck.create!` — and
  # Cards::Fetcher goes to the network for any printing not already held, at roughly 0.7 s each. A
  # list of new printings would otherwise hold that lock for half a minute while every other
  # writer in the app raises SQLite3::BusyException after five seconds. Warmed first, the same
  # transaction closes in milliseconds because every lookup is a local hit.
  def resolve_printings(text)
    text.lines.filter_map { |line| line.strip.match(::Decks::Fetcher::CARD_LINE_RE) }
      .map { |match| [ match[3], match[4] ] }.uniq
      .each { |set_code, number| ::Cards::Fetcher.call("#{::Decks::Fetcher::LIMITLESS_BASE_URL}/#{set_code}/#{number}") }
  end

  def discard_orphaned_list(deck, standing_id)
    return if deck.nil?
    return if TournamentStanding.where(id: standing_id).pick(:deck_id) == deck.id

    deck.destroy_if_ownerless
  end

  def fetch_decklist(url)
    sleep(@pause) if @pause.positive?
    text = Tournaments::LimitlessDecklist.call(url)
    @consecutive_failures = 0
    text
  rescue HttpFetcher::FetchError => e
    @consecutive_failures += 1
    if @consecutive_failures >= CONSECUTIVE_FAILURE_LIMIT
      raise RunAborted, "gave up after #{CONSECUTIVE_FAILURE_LIMIT} consecutive fetch failures (#{e.message})"
    end

    raise
  end

  # /decks/shared prints no author, so the name is the only thing that can situate an ownerless
  # list. Same shape as Tournaments::StandingListImportJob's.
  def deck_name(standing, event)
    "#{standing.player_name} — #{event.name} (#{event.date})"
  end

  def row_label(event, row_plan)
    "#{row_plan.row.player_name} — #{event.name} (#{event.date})"
  end
end
