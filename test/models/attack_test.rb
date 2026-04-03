require "test_helper"

class AttackTest < ActiveSupport::TestCase
  test "belongs to card" do
    attack = attacks(:honedge_cut)
    assert_equal cards(:honedge), attack.card
  end

  test "basic attack without effect" do
    attack = attacks(:honedge_cut)
    assert_equal "Cut", attack.name
    assert_equal "C", attack.cost
    assert_equal "10", attack.damage
    assert_nil attack.effect
    assert_equal 0, attack.position
  end

  test "attack with effect and multiplier damage" do
    attack = attacks(:doublade_weaponized_swords)
    assert_equal "Weaponized Swords", attack.name
    assert_equal "CC", attack.cost
    assert_equal "60×", attack.damage
    assert_includes attack.effect, "Reveal any number of Honedge"
    assert_equal 0, attack.position
  end
end
