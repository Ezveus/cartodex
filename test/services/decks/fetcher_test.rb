require "test_helper"

class Decks::FetcherTest < ActiveSupport::TestCase
  setup do
    @decklist = File.read(Rails.root.join("test/fixtures/files/doublade_dudunsparce.txt"))
    @user = users(:one)
    @original_cards_fetcher_call = Cards::Fetcher.method(:call)
    stub_cards_fetcher
  end

  teardown do
    Cards::Fetcher.define_singleton_method(:call, @original_cards_fetcher_call)
  end

  # --- Happy path ---

  test "creates a deck with correct name" do
    deck = Decks::Fetcher.call(@decklist, @user, "Doublade Dudunsparce")

    assert_equal "Doublade Dudunsparce", deck.name
    assert_equal @user, deck.user
  end

  test "creates deck_cards for all card lines" do
    deck = Decks::Fetcher.call(@decklist, @user, "Doublade Dudunsparce")

    # 11 Pokémon lines + 13 Trainer lines + 2 Energy lines = 26 unique card lines
    assert_equal 26, deck.deck_cards.count
  end

  test "sets correct quantities" do
    deck = Decks::Fetcher.call(@decklist, @user, "Doublade Dudunsparce")

    honedge_dc = deck.deck_cards.joins(:card).find_by(cards: { set_name: "POR", set_number: "56" })
    assert_equal 4, honedge_dc.quantity

    genesect_dc = deck.deck_cards.joins(:card).find_by(cards: { set_name: "BLK", set_number: "67" })
    assert_equal 2, genesect_dc.quantity
  end

  # --- Card name parsing ---

  test "parses card names with special characters" do
    deck = Decks::Fetcher.call(@decklist, @user, "Test")

    # Verify cards were created for lines with special chars
    assert deck.deck_cards.joins(:card).exists?(cards: { set_name: "MEE", set_number: "2" }),
      "Basic {R} Energy should be parsed"
    assert deck.deck_cards.joins(:card).exists?(cards: { set_name: "MEG", set_number: "119" }),
      "Lillie's Determination should be parsed"
    assert deck.deck_cards.joins(:card).exists?(cards: { set_name: "TEF", set_number: "144" }),
      "Buddy-Buddy Poffin should be parsed"
    assert deck.deck_cards.joins(:card).exists?(cards: { set_name: "SVI", set_number: "186" }),
      "Pokégear 3.0 should be parsed"
    assert deck.deck_cards.joins(:card).exists?(cards: { set_name: "BLK", set_number: "67" }),
      "Genesect ex should be parsed"
  end

  # --- Error cases ---

  test "raises ParseError on empty decklist" do
    assert_raises(Decks::Fetcher::ParseError) do
      Decks::Fetcher.call("", @user, "Empty")
    end
  end

  test "raises ParseError when no card lines found" do
    decklist = "Pokémon: 11\nTrainer: 13\nEnergy: 2\n"

    assert_raises(Decks::Fetcher::ParseError) do
      Decks::Fetcher.call(decklist, @user, "No Cards")
    end
  end

  # --- Transaction rollback ---

  test "rolls back if Cards::Fetcher raises" do
    Cards::Fetcher.define_singleton_method(:call) { |_url| raise Cards::Fetcher::ParseError, "boom" }

    assert_no_difference [ "Deck.count", "DeckCard.count" ] do
      assert_raises(Cards::Fetcher::ParseError) do
        Decks::Fetcher.call(@decklist, @user, "Should Fail")
      end
    end
  end

  # --- Calls Cards::Fetcher with correct URLs ---

  test "calls Cards::Fetcher with limitless URLs" do
    fetched_urls = []
    Cards::Fetcher.define_singleton_method(:call) { |url|
      fetched_urls << url
      uri = URI.parse(url)
      segments = uri.path.split("/")
      Card.find_or_create_by!(set_name: segments[2], set_number: segments[3]) do |c|
        c.name = "Card #{segments[2]} #{segments[3]}"
        c.card_type = "Trainer"
        c.rarity = "Common"
      end
    }

    Decks::Fetcher.call(@decklist, @user, "Test")

    assert_includes fetched_urls, "https://limitlesstcg.com/cards/POR/56"
    assert_includes fetched_urls, "https://limitlesstcg.com/cards/POR/57"
    assert_includes fetched_urls, "https://limitlesstcg.com/cards/MEE/2"
    assert_equal 26, fetched_urls.size
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
end
