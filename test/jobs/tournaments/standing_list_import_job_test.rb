require "test_helper"

class Tournaments::StandingListImportJobTest < ActiveSupport::TestCase
  setup do
    @contributor = users(:one)
    @standing = tournament_standings(:ash_masters)
    @tournament = @standing.tournament
    @decklist = File.read(Rails.root.join("test/fixtures/files/doublade_dudunsparce.txt"))
    @import = @contributor.imports.create!(kind: "standing_list", label: "Ash Ketchum's list")
    @original_cards_fetcher_call = Cards::Fetcher.method(:call)
    stub_cards_fetcher
  end

  teardown do
    Cards::Fetcher.define_singleton_method(:call, @original_cards_fetcher_call)
  end

  test "the imported list belongs to nobody, is shared, virtual, and attached to the standing" do
    assert_difference -> { Deck.count }, 1 do
      Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)
    end

    deck = @standing.reload.deck
    assert_not_nil deck
    assert_nil deck.user_id
    assert_predicate deck, :shared?
    refute_predicate deck, :physical?
    assert_equal "completed", @import.reload.status
  end

  test "the list is anchored to the event's pool, not to the current one" do
    # twm_asc, deliberately not twm_por: the standard_pools fixture comment pins
    # StandardPool.current to twm_por in every test, so anchoring the event to twm_por here would
    # make this test pass whether the job reads the event's pool or falls back to the current
    # one — it would not actually distinguish the two.
    @tournament.update!(format: "standard", standard_pool: standard_pools(:twm_asc))
    assert_not_equal standard_pools(:twm_asc), StandardPool.current

    Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)

    assert_equal standard_pools(:twm_asc), @standing.reload.deck.standard_pool
  end

  test "the list's name situates it: /decks/shared prints no author" do
    Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)

    assert_equal "Ash Ketchum — #{@tournament.name} (#{@tournament.date})",
      @standing.reload.deck.name
  end

  # Decks::ImportJob broadcasts into #decks-grid and bumps #deck-count, which would file a
  # tournament field list in the contributor's own deck list — the one thing an ownerless deck
  # must never be. This job broadcasts the standing's row instead.
  test "it broadcasts the row and never the contributor's deck grid" do
    broadcasts = capture_turbo_broadcasts do
      Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)
    end

    assert_empty broadcasts.select { |b| b[:target] == "decks-grid" }
    assert_empty broadcasts.select { |b| b[:target] == "deck-count" }
    replace = broadcasts.find { |b| b[:action] == :replace }
    assert_equal Tournaments::Standings::Row.dom_id(@standing), replace[:target]
    assert_includes replace[:html], "Decklist"
    remove = broadcasts.find { |b| b[:action] == :remove }
    assert_equal "importing-#{@import.id}", remove[:target]
  end

  test "a failure marks the import failed and says so, leaving the standing listless" do
    broadcasts = capture_turbo_broadcasts do
      Tournaments::StandingListImportJob.perform_now(@standing, "not a decklist", @contributor, @import)
    end

    assert_equal "failed", @import.reload.status
    assert_nil @standing.reload.deck
    flash = broadcasts.find { |b| b[:target] == "flash-messages" }
    assert_includes flash[:html], "flash-alert"
  end

  # The import's work is the deck: created and attached before any broadcast runs. A broadcast is
  # a notification about that work, not the work itself, so a broadcast failure must not flip a
  # completed import back to failed — the deck stays put and the contributor's page simply does
  # not update until they reload. Without this, the outer rescue that exists for *real* import
  # failures (Decks::Fetcher raising, a bad decklist) would just as happily catch a raise from
  # rendering the Turbo Stream payload and misreport a fully successful import as failed.
  test "a broadcast failure does not un-complete a successful import" do
    original_replace = Turbo::StreamsChannel.method(:broadcast_replace_to)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) { |*, **|
      raise "broadcast boom"
    }

    Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)

    assert_equal "completed", @import.reload.status
    assert_not_nil @standing.reload.deck
  ensure
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to, original_replace)
  end

  private

  # Both helpers copied from test/jobs/decks/import_job_test.rb, where they were written for the
  # job this one deliberately does not reuse.
  def stub_cards_fetcher
    Cards::Fetcher.define_singleton_method(:call) { |url|
      uri = URI.parse(url)
      segments = uri.path.split("/")
      Card.find_or_create_by!(set_name: segments[2], set_number: segments[3]) do |c|
        c.name = "Card #{segments[2]} #{segments[3]}"
        c.card_type = "Trainer"
        c.rarity = "Common"
      end
    }
  end

  def capture_turbo_broadcasts
    broadcasts = []
    original_append = Turbo::StreamsChannel.method(:broadcast_append_to)
    original_replace = Turbo::StreamsChannel.method(:broadcast_replace_to)
    original_remove = Turbo::StreamsChannel.method(:broadcast_remove_to)

    Turbo::StreamsChannel.define_singleton_method(:broadcast_append_to) { |*args, **kwargs|
      broadcasts << { action: :append, **kwargs }
    }
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) { |*args, **kwargs|
      broadcasts << { action: :replace, **kwargs }
    }
    Turbo::StreamsChannel.define_singleton_method(:broadcast_remove_to) { |*args, **kwargs|
      broadcasts << { action: :remove, **kwargs }
    }

    yield

    broadcasts
  ensure
    Turbo::StreamsChannel.define_singleton_method(:broadcast_append_to, original_append)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to, original_replace)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_remove_to, original_remove)
  end
end
