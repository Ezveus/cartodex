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
