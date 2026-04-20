require "test_helper"

class Decks::TournamentPdfExporterTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
    @profile = tournament_profiles(:ash)
  end

  test "returns a PDF binary" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
    pdf = Decks::TournamentPdfExporter.call(@deck, @profile)

    assert pdf.start_with?("%PDF")
  end

  test "fits a realistic 60-card decklist on a single page" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 2)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 10)
    @deck.deck_cards.create!(card: cards(:special_prism_energy_asc), quantity: 2)

    pdf = Decks::TournamentPdfExporter.call(@deck, @profile)
    page_count = pdf.scan(%r{/Type /Page\b(?!s)}).size

    assert_equal 1, page_count, "Expected 1 page, got #{page_count}"
  end

  test "Pokémon rows keep separate printings (Budew PRE 4 vs Budew ASC 16)" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 2)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

    exporter = Decks::TournamentPdfExporter.new(@deck, @profile)
    rows = exporter.send(:pokemon_rows)

    assert_equal 2, rows.size
    budew_pre = rows.find { |r| r[:set_name] == "PRE" }
    budew_asc = rows.find { |r| r[:set_name] == "ASC" }
    assert_equal 2, budew_pre[:quantity]
    assert_equal "4", budew_pre[:set_number]
    assert_equal "H", budew_pre[:regulation_mark]
    assert_equal 2, budew_asc[:quantity]
    assert_equal "16", budew_asc[:set_number]
    assert_equal "I", budew_asc[:regulation_mark]
  end

  test "Trainer rows merge different printings of the same name" do
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 3)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 1)

    exporter = Decks::TournamentPdfExporter.new(@deck, @profile)
    rows = exporter.send(:trainer_rows)

    assert_equal 1, rows.size
    assert_equal "Boss's Orders", rows.first[:name]
    assert_equal 4, rows.first[:quantity]
  end

  test "Energy rows merge by name and classify basic vs special" do
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 5)
    @deck.deck_cards.create!(card: cards(:special_prism_energy_asc), quantity: 2)
    @deck.deck_cards.create!(card: cards(:special_prism_energy_blk), quantity: 1)

    exporter = Decks::TournamentPdfExporter.new(@deck, @profile)
    rows = exporter.send(:energy_rows)

    assert_equal 2, rows.size
    psychic = rows.find { |r| r[:name] == "Psychic Energy" }
    prism = rows.find { |r| r[:name] == "Prism Energy" }
    assert_equal "Basic", psychic[:kind]
    assert_equal 5, psychic[:quantity]
    assert_equal "Special", prism[:kind]
    assert_equal 3, prism[:quantity]
  end

  test "section totals sum to the deck's total card count" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 3)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 1)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 6)

    exporter = Decks::TournamentPdfExporter.new(@deck, @profile)
    pokemon_total = exporter.send(:pokemon_rows).sum { |r| r[:quantity] }
    trainer_total = exporter.send(:trainer_rows).sum { |r| r[:quantity] }
    energy_total = exporter.send(:energy_rows).sum { |r| r[:quantity] }

    assert_equal @deck.deck_cards.sum(&:quantity), pokemon_total + trainer_total + energy_total
  end
end
