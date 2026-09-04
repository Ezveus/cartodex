require "test_helper"

class Tournaments::StandingsImporterTest < ActiveSupport::TestCase
  DECKLIST_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_decklist.html")).freeze
  LIST_URL = "https://limitlesstcg.com/decks/list/28788".freeze

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

  private

  def import(rows)
    plan = Tournaments::StandingsImportPlan.call(rows: rows)
    Tournaments::StandingsImporter.call(plan: plan, archetype: @archetype, user: @admin)
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
