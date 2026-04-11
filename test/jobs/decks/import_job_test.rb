require "test_helper"

class Decks::ImportJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @decklist = File.read(Rails.root.join("test/fixtures/files/doublade_dudunsparce.txt"))
    @import = @user.imports.create!(kind: "deck", label: "Test Deck")
    @original_cards_fetcher_call = Cards::Fetcher.method(:call)
    stub_cards_fetcher
  end

  teardown do
    Cards::Fetcher.define_singleton_method(:call, @original_cards_fetcher_call)
  end

  # --- Happy path ---

  test "creates a deck via Decks::Fetcher" do
    assert_difference "Deck.count", 1 do
      Decks::ImportJob.perform_now(@decklist, @user, "Test Deck", @import)
    end

    deck = Deck.last
    assert_equal "Test Deck", deck.name
    assert_equal @user, deck.user
    assert_equal "completed", @import.reload.status
  end

  test "broadcasts success flash via Turbo Streams" do
    broadcasts = capture_turbo_broadcasts do
      Decks::ImportJob.perform_now(@decklist, @user, "Test Deck", @import)
    end

    flash_broadcast = broadcasts.find { |b| b[:target] == "flash-messages" }
    assert_not_nil flash_broadcast, "Should broadcast a flash message"
    assert_includes flash_broadcast[:html], "imported successfully"
    assert_includes flash_broadcast[:html], "Test Deck"
  end

  test "broadcasts remove of importing entry" do
    broadcasts = capture_turbo_broadcasts do
      Decks::ImportJob.perform_now(@decklist, @user, "Test Deck", @import)
    end

    remove_broadcast = broadcasts.find { |b| b[:action] == :remove }
    assert_not_nil remove_broadcast, "Should broadcast remove of importing entry"
    assert_equal "importing-#{@import.id}", remove_broadcast[:target]
  end

  test "broadcasts deck count update" do
    broadcasts = capture_turbo_broadcasts do
      Decks::ImportJob.perform_now(@decklist, @user, "Test Deck", @import)
    end

    count_broadcast = broadcasts.find { |b| b[:target] == "deck-count" }
    assert_not_nil count_broadcast, "Should broadcast deck count update"
    assert_includes count_broadcast[:html], @user.decks.count.to_s
  end

  # --- Error path ---

  test "broadcasts failure flash when Decks::Fetcher raises" do
    Cards::Fetcher.define_singleton_method(:call) { |_url| raise "connection failed" }

    broadcasts = capture_turbo_broadcasts do
      Decks::ImportJob.perform_now(@decklist, @user, "Broken Deck", @import)
    end

    flash_broadcast = broadcasts.find { |b| b[:target] == "flash-messages" }
    assert_not_nil flash_broadcast, "Should broadcast an error flash"
    assert_includes flash_broadcast[:html], "failed"
    assert_includes flash_broadcast[:html], "Broken Deck"
  end

  test "broadcasts remove of importing entry on failure" do
    Cards::Fetcher.define_singleton_method(:call) { |_url| raise "boom" }

    broadcasts = capture_turbo_broadcasts do
      Decks::ImportJob.perform_now(@decklist, @user, "Broken Deck", @import)
    end

    remove_broadcast = broadcasts.find { |b| b[:action] == :remove }
    assert_not_nil remove_broadcast
    assert_equal "importing-#{@import.id}", remove_broadcast[:target]
  end

  test "does not create a deck on failure" do
    Cards::Fetcher.define_singleton_method(:call) { |_url| raise "boom" }

    assert_no_difference "Deck.count" do
      Decks::ImportJob.perform_now(@decklist, @user, "Broken Deck", @import)
    end

    assert_equal "failed", @import.reload.status
    assert_equal "boom", @import.error_message
  end

  private

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
