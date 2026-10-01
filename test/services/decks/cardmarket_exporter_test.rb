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

  # missing_only: the copies the member still has to buy (#208).

  test "a physical deck asks only for the copies its collection does not back" do
    @deck.update!(physical: true)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4, owned_copies: 1)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 8, owned_copies: 5)

    output = Decks::CardmarketExporter.call(@deck, missing_only: true)

    assert_equal "3x Boss's Orders\n3x Basic Psychic Energy\n", output
  end

  # The prefix reads the netted count, not the deck's: 1 missing of 3 is a bare line.
  test "a single missing copy loses its quantity prefix" do
    @deck.update!(physical: true)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 3, owned_copies: 2)

    assert_equal "Boss's Orders\n", Decks::CardmarketExporter.call(@deck, missing_only: true)
  end

  # The dropped row sits between the other two, so a filter that left a blank line or broke the
  # name order would show.
  test "a fully backed line is dropped and the rest keep their order" do
    @deck.update!(physical: true)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2, owned_copies: 0)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 6, owned_copies: 0)

    assert_equal "2x Boss's Orders\n6x Basic Psychic Energy\n",
                 Decks::CardmarketExporter.call(@deck, missing_only: true)
  end

  # Only what the deck backs is netted off (#208's scope): free copies sitting in the collection
  # are not, since backing is not re-derived here.
  test "free copies in the collection are not netted off" do
    @deck.update!(physical: true)
    @deck.user.collections.find_or_initialize_by(card: cards(:trainer_card)).update!(quantity: 4)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4, owned_copies: 0)

    assert_equal "4x Boss's Orders\n", Decks::CardmarketExporter.call(@deck, missing_only: true)
  end

  test "a physical deck with nothing left to buy exports nothing at all" do
    @deck.update!(physical: true)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2, owned_copies: 2)

    assert_equal "", Decks::CardmarketExporter.call(@deck, missing_only: true)
  end

  # The full export is untouched by owned_copies, so buying a second copy of the deck stays possible.
  test "the full export of a physical deck still asks for every copy" do
    @deck.update!(physical: true)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4, owned_copies: 4)

    assert_equal "4x Boss's Orders\n", Decks::CardmarketExporter.call(@deck)
  end

  # owned_copies is 0 on a non-physical deck by validation, so this cannot be built through the
  # model; written past it, it proves the rule is "only a physical deck nets" and not an accident
  # of that validation.
  test "a non-physical deck asks for every copy even when missing_only" do
    @deck.update!(physical: false)
    dc = @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)
    dc.update_column(:owned_copies, 3)

    assert_equal "4x Boss's Orders\n", Decks::CardmarketExporter.call(@deck, missing_only: true)
  end
end
