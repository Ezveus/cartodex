require "test_helper"

class Decks::CardmarketExporterTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  test "lists a lone-copy card without quantity prefix" do
    card = cards(:trainer_card)
    @deck.deck_cards.create!(card: card, quantity: 1)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "Boss's Orders\n", output
  end

  test "prefixes multi-copy cards with Nx" do
    card = cards(:trainer_card)
    @deck.deck_cards.create!(card: card, quantity: 3)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "3x Boss's Orders\n", output
  end

  test "appends abilities and attacks to Pokémon names" do
    pokemon = cards(:honedge)
    pokemon.abilities.create!(name: "Sharp Edge", position: 0)
    @deck.deck_cards.create!(card: pokemon, quantity: 2)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "2x Honedge Sharp Edge Cut\n", output
  end

  test "omits abilities/attacks for non-Pokémon cards" do
    trainer = cards(:trainer_card)
    @deck.deck_cards.create!(card: trainer, quantity: 2)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "2x Boss's Orders\n", output
  end

  test "orders lines by card name" do
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 1)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "Boss's Orders\nHonedge Cut\n", output
  end

  test "appends Cardmarket variant tag for trainers when URL is known" do
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 2)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "2x Boss's Orders V2\n", output
  end

  # Every shape below is one the real catalogue's cardmarket_url column holds.
  {
    "Bosss-Orders-PAL172"            => "Boss's Orders",
    "Bosss-Orders-SV1en196"          => "Boss's Orders",
    "Bosss-Orders-V1-SV1en166"       => "Boss's Orders V1",
    "Bosss-Orders-SVEen001"          => "Boss's Orders",
    "Bosss-Orders-SV1en"             => "Boss's Orders",
    "Bosss-Orders-SVP"               => "Boss's Orders",
    "Bosss-Orders-V2-CRZGG11"        => "Boss's Orders V2",
    "Bosss-Orders-V1"                => "Boss's Orders V1",
    "Bosss-Orders-Ghetsis-MEG114"    => "Boss's Orders Ghetsis",
    "Bosss-Orders-Ghetsis"           => "Boss's Orders Ghetsis",
    "Bosss-Orders-Corbeau-V1-ASC183" => "Boss's Orders Corbeau V1"
  }.each do |slug, expected|
    test "reads the variant out of a #{slug} product slug" do
      card = cards(:trainer_card)
      card.update_column(:cardmarket_url, "https://www.cardmarket.com/en/Pokemon/Products/Singles/Some-Set/#{slug}")
      @deck.deck_cards.create!(card: card, quantity: 1)

      assert_equal "#{expected}\n", Decks::CardmarketExporter.call(@deck)
    end
  end

  test "keeps the hyphen of a card name when matching it against the slug" do
    card = cards(:trainer_card)
    card.update_columns(name: "U-Turn Board",
                        cardmarket_url: "https://www.cardmarket.com/en/Pokemon/Products/Singles/Unified-Minds/U-Turn-Board-V1-UNM211")
    @deck.deck_cards.create!(card: card, quantity: 1)

    assert_equal "U-Turn Board V1\n", Decks::CardmarketExporter.call(@deck)
  end

  test "skips the Tera ability when exporting Tera Pokémon" do
    ogerpon = cards(:teal_mask_ogerpon_ex)
    ogerpon.abilities.create!(name: "Tera", position: 0)
    ogerpon.abilities.create!(name: "Teal Dance", position: 1)
    @deck.deck_cards.create!(card: ogerpon, quantity: 4)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "4x Teal Mask Ogerpon ex Teal Dance Myriad Leaf Shower\n", output
  end

  test "prefixes basic energies with Basic" do
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 8)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "8x Basic Psychic Energy\n", output
  end

  test "leaves special energies untouched" do
    @deck.deck_cards.create!(card: cards(:special_prism_energy_asc), quantity: 2)

    output = Decks::CardmarketExporter.call(@deck)

    assert_equal "2x Prism Energy\n", output
  end
end
