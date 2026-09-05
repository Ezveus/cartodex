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
  # Five *rows* in a row lost to a transport failure means the far side has stopped answering, and
  # every further request makes the block being handed to us more deserved. Counted per row and not
  # per request, because a row makes up to sixteen of them: a rate limit that lets the decklist page
  # through and refuses the card pages is still a run that has stopped working, and a counter reset
  # by any single successful request would never reach five. A decklist that merely will not parse
  # is not counted — the far side plainly answered — but it does not clear the count either, since
  # nothing about that row succeeded.
  CONSECUTIVE_FAILURE_LIMIT = 5

  # The four counts answer four different questions and deliberately do not sum to the row count.
  # `created` is "a standing row now exists" and is counted the moment it does, whether or not its
  # field list then arrived — the row is a real record either way, and its missing list is reported
  # separately in `failures`. `enriched` is "a list was attached to a row that had none", which is
  # only true once the attach succeeds. `skipped` and `blocked` never touch the database at all.
  Result = Struct.new(
    :created, :enriched, :skipped, :blocked, :standing_ids, :enriched_standing_ids, :failures,
    :aborted_reason, keyword_init: true
  ) do
    def aborted? = aborted_reason.present?
    def failed_count = failures.size
  end

  # `pause` is injectable and zero by default so tests do not sleep, but the job passes a real one:
  # a run is hundreds of requests to somebody else's site in a tight loop, and nothing else in this
  # app asks Limitless for that much at once.
  def initialize(plan:, archetype:, user:, pause: 0.0, failure_limit: CONSECUTIVE_FAILURE_LIMIT)
    @plan = plan
    @archetype = archetype
    @user = user
    @pause = pause
    @failure_limit = failure_limit
    @standing_ids = []
    @enriched_standing_ids = []
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
      standing_ids: @standing_ids, enriched_standing_ids: @enriched_standing_ids,
      failures: @failures, aborted_reason: aborted_reason
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
  # find_or_create_by hands back an unpersisted record without raising a thing.
  #
  # Both rescues are needed, and the *validation* one is the likely path. A member who catalogues
  # this event between the preview and the write loses to `name_and_date_are_unique`, a non-atomic
  # `exists?` that fires long before the UNIQUE index can — so the common race surfaces as
  # RecordInvalid, and only a genuinely simultaneous insert reaches RecordNotUnique. Rescuing just
  # the latter blocked every row of the event instead of reusing the row somebody else had just
  # made. The re-find is guarded: a RecordInvalid that was *not* the uniqueness clash (a tier the
  # enum refuses, say) must still be reported rather than turned into a lookup miss.
  def find_or_create_tournament(event)
    return event.tournament if event.tournament

    Tournament.create!(
      name: event.name, date: event.date, tier: event.tier, format: event.format,
      other_format_name: event.other_format_name, standard_pool: event.standard_pool,
      created_by: @user
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    catalogued_meanwhile(event) || raise
  end

  def catalogued_meanwhile(event)
    Tournament.find_by(name_normalized: event.name.squish.downcase, date: event.date)
  end

  def import_row(tournament, event, row_plan)
    case row_plan.status
    when :create then create_standing(tournament, event, row_plan)
    when :enrich then enrich_standing(event, row_plan)
    else @counts[row_plan.status] += 1
    end
    @consecutive_failures = 0
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
  #
  # The row is re-read rather than written through the object the plan matched, because standings
  # are wiki-governed and a run walks hundreds of them: a member deleting theirs in between leaves
  # `update!` returning true against nothing at all — Rails does not raise for it — and the field
  # list this had just built would be a shared, ownerless deck referenced by no row, listed on
  # /decks/shared, deletable through no path in the app. That is precisely the orphan D10 orders
  # the writes to prevent, arriving by the other door.
  def enrich_standing(event, row_plan)
    standing = TournamentStanding.find_by(id: row_plan.standing.id)
    raise ActiveRecord::RecordNotFound, "the standing was deleted while the import was running" if standing.nil?

    attach_field_list(standing, event, row_plan.row)
    @enriched_standing_ids << standing.id
    @counts[:enrich] += 1
  end

  # The order is what keeps an orphan from existing: Decks::Fetcher commits its own transaction, so
  # a list built before its standing is a shared, ownerless deck referenced by nothing the moment
  # the standing fails to validate — reachable on /decks/shared and deletable through no path in
  # the app. `deck` is optional on a standing, so the standing goes first and the list is attached
  # after, with the same discard guard Tournaments::StandingListImportJob already carries.
  def attach_field_list(standing, event, row)
    return if row.list_url.blank?

    text = remote { Tournaments::LimitlessDecklist.call(row.list_url) }
    resolve_printings(text)
    deck = ::Decks::Fetcher.call(
      text, nil, deck_name(standing, event),
      shared: true, format: event.format, standard_pool: event.standard_pool,
      other_format_name: event.other_format_name
    )

    # Defensive: the standing was valid moments ago and its `tournament` association is already
    # loaded, so the reachable failure here is not a validation but the row having been deleted —
    # which `update!` reports by returning true, and confirm_attached! is what actually catches.
    begin
      standing.update!(deck: deck)
    rescue StandardError
      discard_orphaned_list(deck, standing.id)
      raise
    end

    confirm_attached!(deck, standing.id)
  end

  # `update!` returns true even when the row it targets is gone: Rails does not raise for an UPDATE
  # that matched nothing. Standings are wiki-governed and a run walks hundreds of them, so a member
  # deleting theirs in between is an ordinary event — and taking that `true` at face value would
  # leave the list just built as a shared, ownerless deck referenced by no row, listed on
  # /decks/shared and deletable through no path in the app. So the write is confirmed against the
  # database rather than assumed, which also covers the window the re-read in #enrich_standing
  # cannot: the seconds spent fetching and building the list.
  def confirm_attached!(deck, standing_id)
    return if TournamentStanding.where(id: standing_id).pick(:deck_id) == deck.id

    deck.destroy_if_ownerless
    raise ActiveRecord::RecordNotFound, "the standing was deleted while its field list was being imported"
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
      .each { |set_code, number| resolve_printing(set_code, number) }
  end

  # The pause and the failure counter apply to a printing Cards::Fetcher will actually go and get.
  # Asking first costs one indexed lookup and is what keeps a re-import — where every printing is
  # already held — from sleeping fifteen times per row for nothing.
  def resolve_printing(set_code, number)
    url = "#{::Decks::Fetcher::LIMITLESS_BASE_URL}/#{set_code}/#{number}"
    return ::Cards::Fetcher.call(url) if Card.exists?(set_name: set_code, set_number: number)

    remote { ::Cards::Fetcher.call(url) }
  end

  def discard_orphaned_list(deck, standing_id)
    return if deck.nil?
    return if TournamentStanding.where(id: standing_id).pick(:deck_id) == deck.id

    deck.destroy_if_ownerless
  end

  # Everything that leaves this machine goes through here: it is the one place that paces the run
  # and the one place that notices the far side has stopped answering. It wraps the card pages as
  # well as the decklist page because a 429 landing on /cards/... is the same event as one landing
  # on /decks/list/..., and the card pages are fifteen sixteenths of the traffic. The count is
  # cleared by a row that completed, never by one request that happened to get through — see
  # CONSECUTIVE_FAILURE_LIMIT.
  def remote
    sleep(@pause) if @pause.positive? && @requested
    @requested = true
    yield
  rescue HttpFetcher::FetchError => e
    @consecutive_failures += 1
    if @consecutive_failures >= @failure_limit
      raise RunAborted, "gave up after #{@failure_limit} consecutive fetch failures (#{e.message})"
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
