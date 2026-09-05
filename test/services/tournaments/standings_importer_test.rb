require "test_helper"

class Tournaments::StandingsImporterTest < ActiveSupport::TestCase
  DECKLIST_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_decklist.html")).freeze
  LIST_URL = "https://limitlesstcg.com/decks/list/28788".freeze

  # The online source hands the importer a decklist *service* rather than a page, so these are the
  # texts that service returns. LIST_A_SHUFFLED is the same cards in a different column order — the
  # layout a decklist page really varies in, and the case a key made of the raw text cannot see.
  URL_A = "https://play.limitlesstcg.com/tournament/aaa/player/jrobrueda/decklist".freeze
  URL_B = "https://play.limitlesstcg.com/tournament/bbb/player/jrobrueda/decklist".freeze
  URL_C = "https://play.limitlesstcg.com/tournament/ccc/player/jrobrueda/decklist".freeze

  LIST_A = <<~TEXT.freeze
    Pokémon: 3
    2 Raging Bolt ex TEF 123
    1 Teal Mask Ogerpon ex TWM 25

    Trainer: 4
    4 Crispin TWM 133
  TEXT

  LIST_A_SHUFFLED = <<~TEXT.freeze
    Trainer: 4
    4 Crispin TWM 133

    Pokémon: 3
    1 Teal Mask Ogerpon ex TWM 25
    2 Raging Bolt ex TEF 123
  TEXT

  setup do
    @admin = users(:one)
    @archetype = archetypes(:standings_marker)
    @original_http = HttpFetcher.method(:call)
    @original_cards_fetcher = Cards::Fetcher.method(:call)
    @fetch_depths = []
    stub_http(DECKLIST_HTML)
    stub_cards_fetcher
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http)
    Cards::Fetcher.define_singleton_method(:call, @original_cards_fetcher)
  end

  test "creates the event, its standings and their field lists" do
    result = import([ row(player_name: "Tomi Markkula", placement: 4) ])

    tournament = Tournament.find_by(name_normalized: "world championships 2026")
    assert_equal Date.new(2026, 8, 28), tournament.date
    assert_equal "worlds", tournament.tier
    assert_equal @admin, tournament.created_by

    standing = tournament.standings.sole
    assert_equal [ "Tomi Markkula", "masters", 4, @archetype, @admin ],
      [ standing.player_name, standing.division, standing.placement, standing.archetype, standing.created_by ]
    assert_equal 1, result.created
    assert_equal [ standing.id ], result.standing_ids

    # A field list is a Deck owned by nobody, shared (that is the only listing that can show it)
    # and anchored to the event's own pool rather than to StandardPool.current.
    deck = standing.deck
    assert_nil deck.user_id
    assert deck.shared?
    assert_equal StandardPool.at(tournament.date), deck.standard_pool
    assert_equal 15, deck.deck_cards.count
  end

  # The blocker this test exists for: Decks::Fetcher wraps its whole body in serialized_transaction,
  # which on SQLite takes the database's single write lock at Deck.create!, and Cards::Fetcher goes
  # to the network for any printing not already held. Resolve the printings inside that transaction
  # and one list holds the lock across ~15 HTTP round trips while every other writer in the app
  # raises SQLite3::BusyException after five seconds. Here every network-costing resolution has to
  # happen at the outermost transaction depth — the fixtures' own — never nested inside another.
  test "resolves every printing before the deck transaction opens" do
    import([ row ])

    # Two of the list's fifteen printings are already fixtures, so the exact count is not the
    # point — that none of the remaining resolutions happened inside a nested transaction is.
    assert_predicate @fetch_depths, :any?
    assert_equal [], @fetch_depths.reject { |depth| depth == 1 }
  end

  test "reuses an event that is already catalogued" do
    assert_no_difference -> { Tournament.count } do
      import([ row(event_name: "Regional Championship", event_date: Date.new(2026, 3, 14), player_name: "Brock") ])
    end

    assert_equal tournaments(:one), TournamentStanding.find_by(player_name: "Brock").tournament
  end

  # Enrichment fills a NULL deck_id and touches nothing else. Every other column on an existing row
  # was typed by a member, and rewriting it would make this a republish rather than an import.
  test "attaches a field list to an existing standing without rewriting it" do
    standing = tournament_standings(:ash_masters)
    before = standing.slice(:player_name, :placement, :wins, :losses, :ties, :archetype_id, :created_by_id)

    result = import([ row(event_name: "Regional Championship", event_date: Date.new(2026, 3, 14),
      player_name: "Ash Ketchum", placement: 33) ])

    standing.reload
    assert_equal before, standing.slice(*before.keys)
    assert_not_nil standing.deck
    assert_equal 1, result.enriched
    assert_equal 0, result.created
    # On the receipt separately from the rows the run created, because undo treats the two
    # oppositely: it deletes what it made and only takes the list back off what it did not.
    assert_equal [ standing.id ], result.enriched_standing_ids
    assert_empty result.standing_ids
  end

  test "leaves a standing that already has a list alone" do
    result = import([ row(event_name: "Regional Championship", event_date: Date.new(2026, 3, 14),
      player_name: "Ash Ketchum", placement: 33, list_url: nil) ])

    assert_equal 1, result.skipped
    assert_nil tournament_standings(:ash_masters).reload.deck
  end

  # One unparseable list out of forty is not a reason to abandon the other thirty-nine, and a run
  # that silently dropped it would be worse than one that says which row it refused.
  test "reports a bad row by name and keeps going" do
    stub_http(->(url) {
      raise Tournaments::LimitlessDecklist::ParseError, "boom" if url.end_with?("/99999")

      DECKLIST_HTML
    })

    result = import([
      row(player_name: "Good One", placement: 1),
      row(player_name: "Bad One", placement: 2, list_url: "https://limitlesstcg.com/decks/list/99999")
    ])

    assert_equal 2, result.created
    assert_equal 1, result.failed_count
    assert_match(/Bad One — World Championships 2026/, result.failures.first.first)
    assert_not_nil TournamentStanding.find_by(player_name: "Good One").deck
    # The standing survives its missing list: a placement and an archetype is still a record.
    assert_nil TournamentStanding.find_by(player_name: "Bad One").deck
  end

  # The standing is written first and the list attached after, precisely so that a row which fails
  # to validate cannot leave a shared, ownerless deck behind — Decks::Fetcher commits its own
  # transaction, and nothing in the app can delete such a deck except the standing that owns it.
  test "creates no field list for a row the event refuses" do
    tournaments(:one).update!(masters_participant_count: 10)

    assert_no_difference -> { Deck.count } do
      result = import([ row(event_name: "Regional Championship", event_date: Date.new(2026, 3, 14),
        player_name: "Brock", placement: 33) ])

      assert_equal 1, result.failed_count
      assert_match(/masters field/, result.failures.first.last)
    end
  end

  # Five refusals in a row means the far side is rate-limiting or down. Collecting three hundred
  # identical failures under a green status would be a lie, and every further request makes the
  # block being handed to us more deserved.
  test "gives up after five consecutive fetch failures" do
    stub_http(->(_url) { raise HttpFetcher::FetchError, "HTTP 429" })

    result = import(Array.new(8) { |i| row(player_name: "P#{i}", placement: i + 1) })

    assert result.aborted?
    assert_match(/5 consecutive fetch failures/, result.aborted_reason)
    # The standings themselves were written — only the lists could not be fetched.
    assert_equal 5, result.failed_count
  end

  # The card pages are the bulk of a run's traffic — up to fifteen per row against one decklist
  # page — so a rate limit lands on them first. Counting only the decklist fetches let a
  # rate-limited run hammer on to the end and report success.
  test "gives up when it is the card pages that stop answering" do
    Cards::Fetcher.define_singleton_method(:call) { |_url| raise HttpFetcher::FetchError, "HTTP 429" }

    result = import(Array.new(8) { |i| row(player_name: "P#{i}", placement: i + 1) })

    assert result.aborted?
    assert_match(/consecutive fetch failures/, result.aborted_reason)
    # Five rows tried, not eight: the run stops rather than working through the rest.
    assert_equal 5, result.failed_count
  end

  # "Consecutive" has to mean consecutive. A patch of bad luck around one row that went through is
  # not a far side that has stopped answering, and a run that gave up on it would strand rows an
  # admin has no way to import except by running the whole thing again.
  test "a row that goes through clears the count" do
    stub_http(->(url) { url.end_with?("/4") ? DECKLIST_HTML : raise(HttpFetcher::FetchError, "HTTP 429") })

    result = import(Array.new(9) { |i|
      row(player_name: "P#{i}", placement: i + 1, list_url: "https://limitlesstcg.com/decks/list/#{i}")
    })

    assert_not result.aborted?, result.aborted_reason
    assert_equal 8, result.failed_count
    assert_equal 9, result.created
  end

  test "counts a blocked event's rows without touching the database" do
    assert_no_difference [ -> { Tournament.count }, -> { TournamentStanding.count } ] do
      result = import([ row(event_date: Date.new(2024, 11, 2), event_name: "Regional Antwerp") ])

      assert_equal 1, result.blocked
      assert_equal 0, result.created
      # A blocked event is a decision the plan already made and printed; it is not a failure to
      # report a second time, and the guard that returns early is the only thing keeping the run
      # from trying to create the event anyway.
      assert_empty result.failures
    end
  end

  # A member catalogues the event between the preview and the write. `name_and_date_are_unique` is
  # a validation, so it fires long before the UNIQUE index can — rescuing only RecordNotUnique
  # blocked every row of the event instead of using the row somebody else had just made.
  test "reuses an event catalogued while the run was walking it" do
    original = Tournament.method(:create!)
    Tournament.define_singleton_method(:create!) { |*args, **kwargs|
      Tournament.define_singleton_method(:create!, original)
      original.call(name: "World Championships 2026", date: Date.new(2026, 8, 28), tier: "worlds",
        format: "standard", standard_pool: StandardPool.at(Date.new(2026, 8, 28)))
      original.call(*args, **kwargs)
    }

    result = import([ row(player_name: "Tomi Markkula", placement: 4) ])

    assert_empty result.failures
    assert_equal 1, result.created
    assert_equal 1, Tournament.where(name_normalized: "world championships 2026").count
  ensure
    Tournament.define_singleton_method(:create!, original)
  end

  # A member deletes their own row while the run is fetching its list. `update!` against a row that
  # no longer exists returns true without raising, so the list would otherwise be left ownerless,
  # shared, and referenced by nothing.
  test "destroys a field list whose standing vanished mid-import" do
    standing = tournament_standings(:ash_masters)
    original = ::Decks::Fetcher.method(:call)
    ::Decks::Fetcher.define_singleton_method(:call) { |*args, **kwargs|
      deck = original.call(*args, **kwargs)
      TournamentStanding.where(id: standing.id).delete_all
      deck
    }

    before = Deck.pluck(:id)
    result = import([ row(event_name: "Regional Championship", event_date: Date.new(2026, 3, 14),
      player_name: "Ash Ketchum", placement: 33) ])

    assert_equal 1, result.failed_count
    assert_match(/deleted while its field list/, result.failures.first.last)
    # An exact-set comparison, not a count: decks(:field_list) is itself an ownerless deck, so
    # "no ownerless decks" would be false before the run as well as after it.
    assert_equal before.sort, Deck.pluck(:id).sort
  ensure
    ::Decks::Fetcher.define_singleton_method(:call, original)
  end

  # ---- the online source, and its de-duplication pre-pass -------------------------------------

  test "writes an online event with its attendance, and the row's own record" do
    result = online_import([ online_row(placement: 2, wins: 8, losses: 0, ties: 1) ],
      lists: { URL_A => LIST_A })

    standing = TournamentStanding.find(result.standing_ids.sole)
    tournament = standing.tournament
    assert tournament.online?
    # The leaderboard prints the field size on every row; the paper source publishes none, which is
    # why this is the first participant count anything in this app has ever written.
    assert_equal 197, tournament.open_participant_count
    # "other" whatever the name says, and never a guess: CP_REFERENCE would otherwise offer
    # championship points for an online event.
    assert_equal "other", tournament.tier
    assert_equal standard_pools(:twm_por), tournament.standard_pool
    assert_equal [ "open", 2, 8, 0, 1 ],
      [ standing.division, standing.placement, standing.wins, standing.losses, standing.ties ]
  end

  # The defect that would otherwise appear only on the second click. A row already imported is
  # :skip, and a :skip row never fetches its decklist — so a pre-pass that skipped them would
  # compare the survivors against an empty set and create every row it dropped last time, which is
  # the exact one-player weighting the de-duplication exists to prevent.
  test "importing the same leaderboard twice writes the same standings the second time" do
    lists = { URL_A => LIST_A, URL_B => LIST_A, URL_C => LIST_A }

    first = online_import(one_players_three_entries, lists: lists)
    assert_equal 1, first.created
    assert_equal 2, first.duplicates

    second = nil
    assert_no_difference [ -> { Tournament.count }, -> { TournamentStanding.count }, -> { Deck.count } ] do
      second = online_import(one_players_three_entries, lists: lists)
    end

    assert_equal 0, second.created
    assert_equal 1, second.skipped
    assert_equal 2, second.duplicates
    assert_empty second.failures
  end

  # StandingsImportPlan sorts its events by date descending and import_event is the loop unit, so
  # "the first row met" is decided by the event's date. Here the later event holds the worse finish,
  # so the two orders disagree and only a survivor chosen by placement is the best finish.
  test "keeps the best placement of a duplicate group, not the first row it reaches" do
    result = online_import(one_players_two_entries, lists: { URL_A => LIST_A, URL_B => LIST_A })

    assert_equal 1, result.created
    assert_equal 1, result.duplicates
    standing = TournamentStanding.find(result.standing_ids.sole)
    assert_equal [ "Weekly A", 1 ], [ standing.tournament.name, standing.placement ]
  end

  # find_or_create_tournament runs before the first row, and the leaderboard carries roughly one row
  # per event — so without a guard every dropped row leaves a Tournament nothing points at, which
  # StandingsImportUndo never deletes, no admin screen lists, and neither the catalog nor search
  # shows. Nothing anywhere in the app could remove it again.
  test "never creates an event whose only row was de-duplicated away" do
    Tournament.create!(name: "Weekly A", date: Date.new(2026, 2, 20), online: true, tier: "other",
      format: "standard", standard_pool: standard_pools(:twm_por))

    assert_no_difference -> { Tournament.count } do
      result = online_import(one_players_two_entries, lists: { URL_A => LIST_A, URL_B => LIST_A })

      assert_equal 1, result.created
      assert_equal 1, result.duplicates
    end

    assert_nil Tournament.find_by(name_normalized: "weekly b")
  end

  # Two people arriving at one 60 is a fact about the build, not one person's registration habit —
  # so the key is (player slug, content) and never the content alone.
  test "keeps one identical list played by two different people" do
    rows = [
      online_row(placement: 1, list_url: URL_A),
      online_row(player_name: "Aruaru", player_slug: "aruarupokeka", placement: 2, list_url: URL_B)
    ]

    result = online_import(rows, lists: { URL_A => LIST_A, URL_B => LIST_A })

    assert_equal 2, result.created
    assert_equal 0, result.duplicates
  end

  # A row carrying no decklist has no content to compare, so it can never be the duplicate of
  # another one — least of all of a second contentless row belonging to the same player.
  test "keeps every row of one player that carries no decklist at all" do
    rows = [
      online_row(event_name: "Weekly A", event_date: Date.new(2026, 2, 20), placement: 1,
        list_url: URL_A, event_key: "aaa"),
      online_row(event_name: "Weekly B", event_date: Date.new(2026, 2, 21), placement: 2,
        list_url: nil, event_key: "bbb"),
      online_row(event_name: "Weekly C", event_date: Date.new(2026, 2, 22), placement: 3,
        list_url: nil, event_key: "ccc")
    ]

    result = online_import(rows, lists: { URL_A => LIST_A })

    assert_equal 3, result.created
    assert_equal 0, result.duplicates
  end

  # A pre-pass fetch that fails has no content either, so the row is kept — and it fails again on
  # its own row, where it is reported by name rather than vanishing into a pre-pass no receipt
  # mentions.
  test "keeps a row whose decklist could not be fetched, and reports it by name" do
    result = online_import(one_players_two_entries, lists: { URL_A => LIST_A })

    assert_equal 2, result.created
    assert_equal 0, result.duplicates
    assert_equal 1, result.failed_count
    assert_match(/JRobrueda — Weekly B/, result.failures.first.first)
    assert_nil TournamentStanding.find_by(placement: 9).deck
  end

  # The decklist text is in DOM column order, so one 60 laid out differently survives a string
  # comparison untouched. The key is a sorted multiset of (set, number, quantity).
  test "de-duplicates one list served with its columns in a different order" do
    result = online_import(one_players_two_entries, lists: { URL_A => LIST_A, URL_B => LIST_A_SHUFFLED })

    assert_equal 1, result.created
    assert_equal 1, result.duplicates
  end

  # The paper source is a *field*, where one player appears once and two rows carrying one list are
  # two people. Its runs must be exactly what they were.
  test "de-duplicates nothing when the source did not ask for it" do
    result = online_import(one_players_two_entries, lists: { URL_A => LIST_A, URL_B => LIST_A },
      deduplicate: false)

    assert_equal 2, result.created
    assert_equal 0, result.duplicates
  end

  private

  def import(rows)
    plan = Tournaments::StandingsImportPlan.call(rows: rows)
    Tournaments::StandingsImporter.call(plan: plan, archetype: @archetype, user: @admin)
  end

  def online_import(rows, lists: {}, deduplicate: true, standard_pool: standard_pools(:twm_por))
    plan = Tournaments::StandingsImportPlan.call(rows: rows, online: true, standard_pool: standard_pool)
    Tournaments::StandingsImporter.call(
      plan: plan, archetype: @archetype, user: @admin,
      decklist_service: decklist_service(lists), deduplicate: deduplicate
    )
  end

  # Stands in for Tournaments::OnlineDecklist. Which service turns a URL into decklist text is the
  # one coupling the two sources do not share, and a URL this knows nothing about answers the way
  # the far side going quiet does — which is what the pre-pass has to survive.
  def decklist_service(lists)
    ->(url) { lists.fetch(url) { raise HttpFetcher::FetchError, "HTTP 404 #{url}" } }
  end

  # The same player and the same list at two events, where the later event holds the worse finish —
  # so "first reached" (the plan sorts events newest first) and "best placement" disagree.
  def one_players_two_entries
    [
      online_row(event_name: "Weekly A", event_date: Date.new(2026, 2, 20), placement: 1,
        list_url: URL_A, event_key: "aaa"),
      online_row(event_name: "Weekly B", event_date: Date.new(2026, 2, 25), placement: 9,
        list_url: URL_B, event_key: "bbb")
    ]
  end

  def one_players_three_entries
    one_players_two_entries + [
      online_row(event_name: "Weekly C", event_date: Date.new(2026, 2, 22), placement: 5,
        list_url: URL_C, event_key: "ccc")
    ]
  end

  def online_row(**overrides)
    Tournaments::OnlineResults::Row.new(
      **{
        event_name: "Pumpkaweekly #12", event_date: Date.new(2026, 2, 20),
        division: "open", division_suffix: nil, format: "standard",
        player_name: "JRobrueda", placement: 2, list_url: URL_A,
        player_slug: "jrobrueda", attendance: 197, wins: 8, losses: 0, ties: 0, event_key: "aaa"
      }.merge(overrides)
    )
  end

  def row(**overrides)
    Tournaments::LimitlessResults::Row.new(
      **{
        event_name: "World Championships 2026", event_date: Date.new(2026, 8, 28),
        division: "masters", division_suffix: nil, format: "standard",
        player_name: "Tomi Markkula", placement: 4, list_url: LIST_URL
      }.merge(overrides)
    )
  end

  def stub_http(body)
    HttpFetcher.define_singleton_method(:call) { |url| body.respond_to?(:call) ? body.call(url) : body }
  end

  # Models Cards::Fetcher's real contract rather than replacing it: a printing already held costs
  # nothing, and only an unknown one "goes to the network" — which is the moment whose transaction
  # depth the D7 test is about.
  def stub_cards_fetcher
    depths = @fetch_depths
    Cards::Fetcher.define_singleton_method(:call) { |url|
      segments = URI.parse(url).path.split("/")
      set_name, set_number = segments[2], segments[3]
      existing = Card.find_by(set_name: set_name, set_number: set_number)
      next existing if existing

      depths << ActiveRecord::Base.connection.open_transactions
      Card.create!(name: "Card #{set_name} #{set_number}", card_type: "Trainer", rarity: "Common",
        set_name: set_name, set_number: set_number)
    }
  end
end
