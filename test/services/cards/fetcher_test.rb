require "test_helper"

class Cards::FetcherTest < ActiveSupport::TestCase
  setup do
    @honedge_html = File.read(Rails.root.join("test/fixtures/files/POR_56.html"))
    @doublade_html = File.read(Rails.root.join("test/fixtures/files/POR_57.html"))
    @barbaracle_html = File.read(Rails.root.join("test/fixtures/files/POR_43.html"), encoding: "utf-8")
    @lillie_html = File.read(Rails.root.join("test/fixtures/files/MEG_119.html"), encoding: "utf-8")
    @basic_energy_html = File.read(Rails.root.join("test/fixtures/files/MEE_6.html"), encoding: "utf-8")
    @special_energy_html = File.read(Rails.root.join("test/fixtures/files/POR_87.html"), encoding: "utf-8")
    @mega_zygarde_html = File.read(Rails.root.join("test/fixtures/files/POR_47.html"), encoding: "utf-8")
    @original_http_fetcher_call = HttpFetcher.method(:call)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  # --- URL parsing ---

  test "raises on invalid URL" do
    assert_raises(Cards::Fetcher::ParseError) do
      Cards::Fetcher.call("https://limitlesstcg.com/decks/123")
    end
  end

  # --- Basic card (Honedge POR/56) ---

  test "creates a new card from HTML" do
    cards(:honedge).destroy
    stub_http("https://limitlesstcg.com/cards/POR/56", @honedge_html)

    assert_difference "Card.count", 1 do
      card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")

      assert_equal "Honedge", card.name
      assert_equal "Pokémon", card.card_type
      assert_equal "POR", card.set_name
      assert_equal "56", card.set_number
      assert_equal 70, card.hp
      assert_equal "Metal", card.type_symbol
      assert_equal "Basic", card.stage
      assert_nil card.evolves_from
      assert_equal "Fire", card.weakness
      assert_equal "Grass", card.resistance
      assert_equal 2, card.retreat_cost
      assert_equal "Common", card.rarity
      assert_equal "Perfect Order", card.set_full_name
      assert_equal "J", card.regulation_mark
      assert_equal BigDecimal("0.06"), card.price_usd
      assert_equal BigDecimal("0.06"), card.price_eur
      assert card.image_url.present?
    end
  end

  test "parses attacks for basic card" do
    stub_http("https://limitlesstcg.com/cards/POR/56", @honedge_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")

    assert_equal 1, card.attacks.size
    attack = card.attacks.first
    assert_equal "Cut", attack.name
    assert_equal "C", attack.cost
    assert_equal "10", attack.damage
    assert_nil attack.effect
    assert_equal 0, attack.position
  end

  # --- Stage 1 card (Doublade POR/57) ---

  test "parses stage 1 card with evolves_from" do
    stub_http("https://limitlesstcg.com/cards/POR/57", @doublade_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/57")

    assert_equal "Doublade", card.name
    assert_equal 100, card.hp
    assert_equal "Stage 1", card.stage
    assert_equal "Honedge", card.evolves_from
  end

  test "parses attack with multiplier damage and effect" do
    stub_http("https://limitlesstcg.com/cards/POR/57", @doublade_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/57")

    attack = card.attacks.first
    assert_equal "Weaponized Swords", attack.name
    assert_equal "CC", attack.cost
    assert_equal "60×", attack.damage
    assert_includes attack.effect, "Reveal any number of Honedge"
  end

  # --- Abilities ---

  test "parses abilities" do
    stub_http("https://limitlesstcg.com/cards/POR/43", @barbaracle_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/43")

    assert_equal 1, card.abilities.size
    ability = card.abilities.first
    assert_equal "Stone Arms", ability.name
    assert_includes ability.effect, "Attach a Basic"
    assert_equal 0, ability.position
  end

  # --- Trainer cards ---

  test "parses trainer subtype and effect" do
    stub_http("https://limitlesstcg.com/cards/MEG/119", @lillie_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/MEG/119")

    assert_equal "Trainer", card.card_type
    assert_equal "Supporter", card.subtype
    assert_includes card.effect, "draw 6 cards"
    assert_nil card.hp
  end

  # --- Energy cards ---

  test "parses basic energy" do
    stub_http("https://limitlesstcg.com/cards/MEE/6", @basic_energy_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/MEE/6")

    assert_equal "Energy", card.card_type
    assert_equal "Basic Energy", card.subtype
    assert_nil card.effect
    assert_nil card.rarity
  end

  test "parses special energy with effect" do
    stub_http("https://limitlesstcg.com/cards/POR/87", @special_energy_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/87")

    assert_equal "Energy", card.card_type
    assert_equal "Special Energy", card.subtype
    assert_includes card.effect, "Energy"
  end

  # --- Pokémon subtype ---

  test "detects Mega Evolution ex subtype" do
    stub_http("https://limitlesstcg.com/cards/POR/47", @mega_zygarde_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/47")

    assert_equal "Mega Evolution ex", card.pokemon_subtype.name
    assert card.pokemon_subtype.rule_box
    assert_equal 3, card.pokemon_subtype.prize_cards_on_ko
  end

  test "regular pokemon has no pokemon_subtype" do
    stub_http("https://limitlesstcg.com/cards/POR/56", @honedge_html)

    card = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")

    assert_nil card.pokemon_subtype
  end

  # --- find_or_create behavior ---

  test "updates existing card instead of creating duplicate" do
    stub_http("https://limitlesstcg.com/cards/POR/56", @honedge_html)

    card1 = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")

    assert_no_difference "Card.count" do
      card2 = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")
      assert_equal card1.id, card2.id
    end
  end

  test "replaces attacks on re-fetch" do
    stub_http("https://limitlesstcg.com/cards/POR/56", @honedge_html)

    Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")

    assert_no_difference "Attack.count" do
      Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")
    end
  end

  private

  def stub_http(url, body)
    HttpFetcher.define_singleton_method(:call) { |u| u == url ? body : raise("Unexpected URL: #{u}") }
  end
end
