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

  # --- Repeated printings ---

  test "merges lines naming the same printing into one deck_card" do
    decklist = "1 Doublade POR 57\n2 Honedge POR 56\n2 Honedge POR 56\n"
    fetched_urls = record_fetched_urls

    deck = Decks::Fetcher.call(decklist, @user, "Repeats")

    assert_equal 2, deck.deck_cards.count
    honedge_dc = deck.deck_cards.joins(:card).find_by(cards: { set_name: "POR", set_number: "56" })
    assert_equal 4, honedge_dc.quantity, "repeated lines must be summed, not overwritten"
    # Pins the fetch count and the order of first appearance in one assertion:
    # a last-wins merge fails on the quantity above, a reordering one fails here.
    assert_equal [ "https://limitlesstcg.com/cards/POR/57", "https://limitlesstcg.com/cards/POR/56" ],
      fetched_urls, "one fetch per printing, in order of first appearance"
  end

  test "merges lines whose names differ only in case" do
    decklist = "3 Honedge POR 56\n1 hOnEdGe POR 56\n"
    record_fetched_urls

    deck = Decks::Fetcher.call(decklist, @user, "Sloppy case")

    assert_equal 1, deck.deck_cards.count
    assert_equal 4, deck.deck_cards.first.quantity
  end

  # `ex` and `EX` are not a casing choice: `ex` marks a Ruby & Sapphire,
  # Scarlet & Violet or Mega Evolution card and `EX` a Black & White or XY one,
  # so these name two different cards and must not merge.
  test "refuses to merge an ex card with an EX card" do
    decklist = "3 Iron Hands ex POR 56\n1 Iron Hands EX POR 56\n"
    record_fetched_urls

    error = assert_raises(Decks::Fetcher::ParseError) do
      Decks::Fetcher.call(decklist, @user, "ex vs EX")
    end

    assert_match "Iron Hands ex", error.message
    assert_match "Iron Hands EX", error.message
  end

  test "refuses to merge two lines that name different cards" do
    decklist = "4 Iron Hands ex POR 56\n2 Iron Thorns ex POR 56\n"
    fetched_urls = record_fetched_urls

    error = assert_raises(Decks::Fetcher::ParseError) do
      Decks::Fetcher.call(decklist, @user, "Typo")
    end

    assert_match "Iron Hands ex", error.message
    assert_match "Iron Thorns ex", error.message
    assert_equal [], fetched_urls, "the list is rejected before anything is fetched"
    assert_equal 0, @user.decks.where(name: "Typo").count
  end

  # --- Network ---

  # The headline claim of the change: a decklist whose printings are all on
  # record costs nothing. Every other test in this file replaces Cards::Fetcher
  # wholesale, so this is the only one positioned to see a round trip at all.
  test "issues no HTTP request for a decklist whose printings are all known" do
    original_http = HttpFetcher.method(:call)
    Cards::Fetcher.define_singleton_method(:call, @original_cards_fetcher_call)
    # Fixtures load with updated_at = now. Without this the test would pass just
    # as well against the freshness window this change replaced, and prove nothing.
    Card.update_all(updated_at: 30.days.ago)
    http_calls = []
    HttpFetcher.define_singleton_method(:call) { |url| http_calls << url; raise "unexpected fetch" }

    decklist = "4 Honedge POR 56\n2 Doublade POR 57\n1 Boss's Orders PAL 172\n3 Psychic Energy SVE 5\n"
    deck = begin
      Decks::Fetcher.call(decklist, @user, "All known")
    rescue RuntimeError
      nil # asserted on below, so the fetched URLs name the culprit rather than a parse error
    end

    assert_equal [], http_calls, "a decklist of known printings must not touch the network"
    assert_equal 4, deck.deck_cards.count
  ensure
    HttpFetcher.define_singleton_method(:call, original_http)
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

  # Re-stubs Cards::Fetcher so it also records the URLs it was handed, and
  # returns that list.
  def record_fetched_urls
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
    fetched_urls
  end

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
