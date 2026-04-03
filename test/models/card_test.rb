require "test_helper"

class CardTest < ActiveSupport::TestCase
  test "valid pokémon card" do
    card = cards(:honedge)
    assert card.valid?
  end

  test "valid trainer card without pokémon fields" do
    card = cards(:trainer_card)
    assert card.valid?
  end

  test "requires name" do
    card = cards(:honedge)
    card.name = nil
    assert_not card.valid?
    assert_includes card.errors[:name], "can't be blank"
  end

  test "requires card_type" do
    card = cards(:honedge)
    card.card_type = nil
    assert_not card.valid?
  end

  test "requires valid card_type" do
    card = cards(:honedge)
    card.card_type = "Spell"
    assert_not card.valid?
  end

  test "requires set_name and set_number" do
    card = cards(:honedge)
    card.set_name = nil
    assert_not card.valid?
    card.set_name = "POR"
    card.set_number = nil
    assert_not card.valid?
  end

  test "requires hp for pokémon cards" do
    card = cards(:honedge)
    card.hp = nil
    assert_not card.valid?
  end

  test "requires type_symbol for pokémon cards" do
    card = cards(:honedge)
    card.type_symbol = nil
    assert_not card.valid?
  end

  test "requires retreat_cost for pokémon cards" do
    card = cards(:honedge)
    card.retreat_cost = nil
    assert_not card.valid?
  end

  test "does not require hp for trainer cards" do
    card = cards(:trainer_card)
    card.hp = nil
    assert card.valid?
  end

  test "has many attacks ordered by position" do
    card = cards(:honedge)
    assert_equal 1, card.attacks.size
    assert_equal "Cut", card.attacks.first.name
  end

  test "destroying card destroys attacks" do
    card = cards(:honedge)
    assert_difference "Attack.count", -1 do
      card.destroy
    end
  end
end
