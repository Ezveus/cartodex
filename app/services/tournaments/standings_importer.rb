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

  # The content half of the de-duplication key, and the *only* definition of it: #group_key
  # compares it in memory and #dedup_key_of stores it on the standing, and two spellings would
  # drift the day one of them learned about a new decklist line — after which cross-run
  # de-duplication would stop, silently, with every run still reporting duplicates within itself.
  #
  # A sorted multiset of (set code, number, quantity), never the decklist text: the text is in DOM
  # column order, so one 60 laid out differently survives a string comparison untouched. Hashed
  # rather than stored whole because it is a database column and an index term; SHA-256 because
  # nothing here needs it to be fast and a collision would merge two people's decks.
  #
  # nil for a list with no readable card lines — no list URL, a fetch that failed, a page that
  # parsed to nothing. All three are one fact, "nothing to compare", and a row with no digest is
  # in no group and is therefore never dropped.
  def self.list_digest(text)
    cards = text.to_s.lines
      .filter_map { |line| line.strip.match(::Decks::Fetcher::CARD_LINE_RE) }
      .map { |match| [ match[3], match[4], match[1].to_i ] }
    return if cards.empty?

    Digest::SHA256.hexdigest(cards.sort.map { |set_code, number, quantity|
      "#{set_code} #{number} #{quantity}"
    }.join("\n"))
  end

  # The five counts answer five different questions and deliberately do not sum to the row count.
  # `created` is "a standing row now exists" and is counted the moment it does, whether or not its
  # field list then arrived — the row is a real record either way, and its missing list is reported
  # separately in `failures`. `enriched` is "a list was attached to a row that had none", which is
  # only true once the attach succeeds. `skipped`, `blocked` and `duplicates` never touch the
  # database at all — a duplicate is a row the pre-pass dropped before any write, and it is its own
  # count rather than folded into `skipped` because the two mean opposite things to an admin
  # reading the receipt: skipped is "already there", duplicate is "deliberately not imported".
  Result = Struct.new(
    :created, :enriched, :skipped, :blocked, :duplicates, :standing_ids, :enriched_standing_ids,
    :failures, :aborted_reason, keyword_init: true
  ) do
    def aborted? = aborted_reason.present?
    def failed_count = failures.size
  end

  # `decklist_service` is the one coupling that differs between the two sources: a decklist page is
  # `QUANTITY NAME (SET-NUM)` on limitlesstcg.com and a column layout whose set and number live only
  # in each line's href on play.limitlesstcg.com. Everything else here reads the plan alone.
  #
  # `deduplicate` is off for the paper source and on for the online one, because the two sources
  # publish different things: a paper results page is a *field*, where one player appears once, and
  # the online leaderboard is a player's *best finishes*, where one list entered into six weekly
  # tournaments is six rows. See #deduplicate! for what that costs and why it is a pre-pass.
  #
  # `pause` is injectable and zero by default so tests do not sleep, but the job passes a real one:
  # a run is hundreds of requests to somebody else's site in a tight loop, and nothing else in this
  # app asks Limitless for that much at once.
  def initialize(plan:, archetype:, user:, decklist_service: Tournaments::LimitlessDecklist,
    deduplicate: false, pause: 0.0, failure_limit: CONSECUTIVE_FAILURE_LIMIT)
    @plan = plan
    @archetype = archetype
    @user = user
    @decklist_service = decklist_service
    @deduplicate = deduplicate
    @pause = pause
    @failure_limit = failure_limit
    @standing_ids = []
    @enriched_standing_ids = []
    @failures = []
    @counts = Hash.new(0)
    @consecutive_failures = 0
    # Keyed by identity, never by value: RowPlan is a Struct, so two rows carrying the same player
    # and status are `eql?` and would share one cache entry and one dedup slot.
    @lists = {}.compare_by_identity
  end

  def call
    deduplicate! if @deduplicate
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
      skipped: @counts[:skip], blocked: @counts[:blocked], duplicates: @counts[:duplicate],
      standing_ids: @standing_ids, enriched_standing_ids: @enriched_standing_ids,
      failures: @failures, aborted_reason: aborted_reason
    )
  end

  # ---- de-duplication -------------------------------------------------------------------------

  # The online source is a leaderboard of one player's *best finishes*, not a field: measured over
  # 20 rows of one archetype's PBL page there are 8 distinct 60-card contents, `jrobrueda` holds 8
  # of the rows and six of those are the identical 60 — one list entered into six weekly online
  # tournaments. Imported as they stand, one person's deck is counted six times in the card report
  # and every card in it weighted 30 % of the sample by one player's registration habit. So a
  # (player slug, list content) pair is kept once — 20 rows down to 13 on that page.
  #
  # It is a *pre-pass*, and that is what makes it correct rather than merely cheap. Deciding row by
  # row as the importer reaches them is wrong three times over, all three because the importer never
  # sees the run whole:
  #
  #   * it cannot keep the best finish — import_event is the loop unit and StandingsImportPlan
  #     re-sorts twice, so "the first one met" is decided by event date descending, and those six
  #     identical lists sit in six different events;
  #   * it is not idempotent — a row already imported is :skip, and a :skip row never fetches its
  #     decklist, so on a second run the survivors are compared against an empty set and every row
  #     dropped last time is created, which is the exact weighting this exists to prevent arriving
  #     on the second click;
  #   * it leaves empty events behind — find_or_create_tournament runs before the first row.
  #
  # So every row of every unblocked event, :skip and :enrich included, is fetched and grouped first,
  # and which rows survive becomes a pure function of the leaderboard rather than of what is already
  # in the database. They go through #remote, so the pacing and the consecutive-failure counter
  # still apply — and the row that exhausts the run's patience is named in `failures` before the
  # abort propagates, exactly as the per-row path names it, or the five that stopped the run would
  # be the only failures a receipt never mentions.
  #
  # The fetches are *not* bounded by `max_rows`, which counts importable rows while this fetches
  # every non-blocked one, :skip included. That is immaterial for a source whose page is 20 rows
  # and would not be for a 300-row one, which is why it is written down rather than assumed.
  def deduplicate!
    candidates = dedup_candidates
    candidates.each { |event, row_plan| prefetch(event, row_plan) }

    remaining = drop_already_recorded(candidates)
    remaining.group_by { |_event, row_plan| group_key(row_plan) }
      .each { |key, group| drop_duplicates(group) if key && group.size > 1 }
  end

  # The in-run grouping is pure in the *leaderboard*; the database is not, because the leaderboard
  # is a rolling top-20 that moves. When the survivor a run elected falls off the board — twenty
  # better finishes appear, the ordinary life of a live page — the next run elects a different
  # member of the same group, does not find it, and creates it while the first survivor's row
  # stays. Measured: run 1 over W1@4/W2@7/W3@9 writes W1, run 2 over W2@7/W3@9 writes W2, and one
  # player's one 60 is two lists in the sample. Two smaller doors onto the same accretion, because
  # an in-memory group is only ever this run's rows: an admin splitting a large run with
  # event_filters de-duplicates within each filter alone, and a transient fetch failure leaves its
  # row un-keyed and kept, so the next healthy run enriches it rather than dropping it.
  #
  # So the key is looked up in the database first, before the grouping, in one indexed query per
  # run. A row whose twin is already recorded is dropped whatever page, filter or run produced it.
  def drop_already_recorded(candidates)
    recorded = recorded_dedup_keys
    return candidates if recorded.empty?

    candidates.reject { |event, row_plan|
      key = group_key(row_plan)
      # Its *own* standing is not a twin: a row this run would have skipped anyway is honestly
      # reported as skipped, and calling it a duplicate would say the run deliberately left out a
      # row it had already imported. Only somebody else's row counts against it.
      next false unless key && (recorded[key].to_a - [ row_plan.standing&.id ]).any?

      drop_row(event, row_plan)
      true
    }
  end

  # One query over one archetype's standings, served by index_tournament_standings_on_dedup_key.
  # NULLs are excluded in SQL rather than filtered afterwards, and that is the rule the whole
  # column pair rests on: a NULL means "not an online import" — the paper source publishes no slug
  # and two paper rows sharing a 60 are two real people who both played it — so it must never
  # participate in de-duplication.
  def recorded_dedup_keys
    @recorded_dedup_keys ||= TournamentStanding
      .where(archetype_id: @archetype.id)
      .where.not(player_slug: nil).where.not(list_digest: nil)
      .pluck(:player_slug, :list_digest, :id)
      .group_by { |slug, digest, _id| [ slug, digest ] }
      .transform_values { |rows| rows.map(&:last) }
  end

  # A :blocked row is never written, so letting one win a group would drop a row that would have
  # been — it is the one status excluded. :skip and :enrich are the whole point of the pre-pass.
  def dedup_candidates
    @plan.events.reject(&:blocked?).flat_map { |event|
      event.rows.filter_map { |row_plan| [ event, row_plan ] if row_plan.status != :blocked }
    }
  end

  # A row with no list has nothing to fetch, and a row whose fetch failed stores nothing. Either
  # way #group_key finds no content, the row gets no group key, and it is therefore never dropped.
  def prefetch(event, row_plan)
    return if row_plan.row.list_url.blank?

    @lists[row_plan] = remote { @decklist_service.call(row_plan.row.list_url) }
    # A decklist that arrived is a unit of remote work that completed, so it clears the count for
    # the same reason a finished row does — otherwise four scattered pre-pass failures plus one
    # later row would "give up after five consecutive fetch failures" that were never consecutive.
    @consecutive_failures = 0
  rescue RunAborted => e
    # Named before the re-raise, for the reason import_row names its own: the row that finally
    # exhausted the run's patience belongs in the report beside the four before it rather than
    # vanishing into the abort message.
    @failures << [ row_label(event, row_plan), e.message ]
    raise
  rescue StandardError
    nil
  end

  # (player slug, list content), and both halves are measured. The display name splits `jrobrueda`
  # in two — 20 rows carried 13 display names against 12 slugs — so a name-keyed group counts one
  # person's single list twice. And the content is a **sorted multiset of (set, number, quantity)**,
  # never the decklist text: the text is in DOM column order, so one 60 laid out differently
  # survives a string comparison untouched.
  # One guard covers all three ways a row can have no content — no list URL, a fetch that failed,
  # and a list that parsed to nothing — because they are one fact: nothing to compare. A row with
  # no key is in no group and is therefore never dropped.
  def group_key(row_plan)
    digest = self.class.list_digest(@lists[row_plan])
    return if digest.nil?

    [ player_key(row_plan.row), digest ]
  end

  # The slug when the source has one. The paper source does not, and does not de-duplicate either,
  # so the fallback is the same normalized name TournamentStanding is keyed on rather than nothing.
  def player_key(row)
    slug = row.player_slug if row.respond_to?(:player_slug)
    slug.presence || row.player_name.to_s.squish.downcase
  end

  # The survivor is the best *finish*, read off the source alone: lowest placement, ties broken by
  # the earliest date and then by the event's own id, a total order. Not "the first row met" — that
  # is decided by the plan's sort, and lists identical across different players are three separate
  # groups here rather than one, because two people arriving at one 60 is a fact about the build.
  def drop_duplicates(group)
    _survivor, *dropped = group.sort_by { |event, row_plan| survivor_order(event, row_plan) }
    dropped.each { |event, row_plan| drop_row(event, row_plan) }
  end

  def survivor_order(event, row_plan)
    [ row_plan.row.placement || Float::INFINITY, event.date, event_key(row_plan.row).to_s ]
  end

  def event_key(row)
    row.event_key if row.respond_to?(:event_key)
  end

  # Removed from the plan rather than flagged on it, so every later reader — import_event's own
  # "is there anything left to write" guard included — sees one shape of truth.
  def drop_row(event, row_plan)
    event.rows = event.rows.reject { |candidate| candidate.equal?(row_plan) }
    @counts[:duplicate] += 1
  end

  # ---- writes ---------------------------------------------------------------------------------

  def import_event(event)
    if event.blocked?
      @counts[:blocked] += event.rows.size
      return
    end
    # Nothing this run can write points at this event: every row it had was either dropped by the
    # de-duplication pre-pass or is one no write follows from. find_or_create_tournament runs
    # *before* the first row, so without this guard a de-duplicated online event — the leaderboard
    # carries roughly one row per event — leaves a Tournament nothing references, and there is no
    # way back: StandingsImportUndo deliberately never deletes events, there is no admin tournaments
    # screen, and an online event appears in neither the catalog nor search. The rows that remain
    # are still counted, because a :skip or :blocked row is a decision the receipt has to show.
    if event.tournament.nil? && event.importable_rows.empty?
      event.rows.each { |row_plan| @counts[row_plan.status] += 1 }
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
      # An online event is catalogued because a standing needs a Tournament, not because anybody
      # attended it, so `online` is what keeps twenty weeklies per archetype per pool out of every
      # listing surface. The attendance beside it is the first participant count anything in this
      # app has ever written: the online source prints it on every row, the paper one publishes
      # none, and TournamentStanding#placement_within_division_field is what reads it back.
      online: event.online, open_participant_count: event.participant_count,
      # The source's own id for the event, and for an online run it *is* the event's identity:
      # online names are arbitrary and repeat weekly, so two different tournaments on one day are
      # two rows here and the partial UNIQUE index on external_key is what keeps them from being
      # four. nil for the paper source, whose events are identified by (name, date) as they always
      # were — and nil is why that index is partial, SQLite treating NULLs as distinct.
      external_key: event.external_key,
      created_by: @user
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    catalogued_meanwhile(event) || raise
  end

  # Scoped by venue, exactly as StandingsImportPlan#load_catalogued is, and for a sharper reason
  # than tidiness. `name_and_date_are_unique` is global, so an online event whose name and date
  # happen to match a paper one loses `create!` — and an unscoped find_by then hands back the
  # *paper* event, onto which this run writes a public `open`-division standing. Online names are
  # arbitrary and repeat weekly ("Pumpkaweekly"), and the plan cannot warn: its own lookup is
  # partitioned, so the row previews as :create with no similar-event hint and the admin sees
  # nothing at all. Scoped, the lookup misses and the RecordInvalid re-raises, which is reported
  # per event and is the honest answer.
  def catalogued_meanwhile(event)
    scope = Tournament.where(online: event.online.present?)
    # By the same key the create used, or the recovery answers a different question from the
    # collision: an online event that lost to the external_key index is not findable by a name two
    # weeklies share, and one found by that name would be the wrong event.
    return scope.find_by(external_key: event.external_key) if event.external_key.present?

    scope.find_by(name_normalized: event.name.squish.downcase, date: event.date)
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
    standing = build_standing(tournament, row_plan)
    @standing_ids << standing.id
    @counts[:create] += 1
    attach_field_list(standing, event, row_plan)
  end

  # W-L-T is written when the source carries it, which the paper results page does not — its rows
  # have no record at all, which is why exactly one standing in the database had one before this.
  # `respond_to?` rather than a second Row shape: the two sources share a contract of eight fields
  # and the online one adds to it, so asking is what keeps this readable by both.
  def build_standing(tournament, row_plan)
    row = row_plan.row
    tournament.standings.create!(
      player_name: row.player_name, division: row.division, placement: row.placement,
      **record_of(row), **dedup_key_of(row_plan),
      archetype: @archetype, created_by: @user
    )
  rescue ActiveRecord::RecordNotUnique
    # Lost the race against a member typing this very row. Their version is the one that stands —
    # this is a wiki — so the run reports it rather than trying to win.
    raise ActiveRecord::RecordInvalid.new(tournament.standings.new),
      "a standing for this player was created while the import was running"
  end

  def record_of(row)
    return {} unless row.respond_to?(:wins)

    { wins: row.wins, losses: row.losses, ties: row.ties }
  end

  # The de-duplication key, written onto the row it identifies so the next run can see it — which
  # is the whole of what makes "de-duplicated" survive a leaderboard that moves. See
  # #drop_already_recorded.
  #
  # Empty for a run that does not de-duplicate, which leaves both columns NULL for every paper
  # row: a NULL is "not an online import" and never participates, because the paper source
  # publishes no slug and two paper rows sharing a 60 are two real people who both played it.
  # Written from #player_key and .list_digest, the same two expressions the in-run grouping
  # compares, rather than from row.player_slug and a second parse — one definition each.
  def dedup_key_of(row_plan)
    return {} unless @deduplicate

    { player_slug: player_key(row_plan.row), list_digest: self.class.list_digest(@lists[row_plan]) }
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

    attach_field_list(standing, event, row_plan)
    @enriched_standing_ids << standing.id
    @counts[:enrich] += 1
  end

  # The order is what keeps an orphan from existing: Decks::Fetcher commits its own transaction, so
  # a list built before its standing is a shared, ownerless deck referenced by nothing the moment
  # the standing fails to validate — reachable on /decks/shared and deletable through no path in
  # the app. `deck` is optional on a standing, so the standing goes first and the list is attached
  # after, with the same discard guard Tournaments::StandingListImportJob already carries.
  #
  # Fetching the decklist *text* is not part of that order and never was: it creates nothing, so
  # #deduplicate! is free to do it for every row before the first write and hand the text back
  # here. What must stay exactly where it is — after the standing exists — is Decks::Fetcher,
  # confirm_attached! and discard_orphaned_list, the three steps that can leave a record behind.
  def attach_field_list(standing, event, row_plan)
    row = row_plan.row
    return if row.list_url.blank?

    text = list_text(row_plan)
    resolve_printings(text)
    deck = ::Decks::Fetcher.call(
      text, nil, deck_name(standing, event),
      shared: true, format: event.format, standard_pool: event.standard_pool,
      other_format_name: event.other_format_name
    )

    # The key travels with the list, and it has to: a row *enriched* with a list is keyed for the
    # first time here, and a row whose pre-pass fetch failed is keyed from the text its own turn
    # finally fetched. Leave either NULL and the next run finds no twin and writes a second list —
    # the transient-failure door onto exactly the accretion #drop_already_recorded closes.
    #
    # Defensive: the standing was valid moments ago and its `tournament` association is already
    # loaded, so the reachable failure here is not a validation but the row having been deleted —
    # which `update!` reports by returning true, and confirm_attached! is what actually catches.
    begin
      standing.update!(deck: deck, **dedup_key_of(row_plan))
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

  # The pre-pass's text when it has one. A prefetch that failed stores nothing, so the row fetches
  # its own list here and fails again — where the failure is reported against the row by name
  # instead of against a pre-pass no receipt mentions.
  # Stored back rather than merely returned: #dedup_key_of digests @lists, so a row whose prefetch
  # failed would otherwise be written with a NULL digest despite having a list attached — and the
  # next run, finding no twin, would build that list a second time on a second row.
  def list_text(row_plan)
    return @lists[row_plan] if @lists.key?(row_plan)

    @lists[row_plan] = remote { @decklist_service.call(row_plan.row.list_url) }
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
