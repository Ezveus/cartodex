require "test_helper"

class ArchetypeTest < ActiveSupport::TestCase
  test "search matches on the archetype name" do
    assert_includes Archetype.search("Ogerpon"), archetypes(:ogerpon)
  end

  test "search matches on a member Pokémon's name" do
    assert_includes Archetype.search("Budew"), archetypes(:budew_ogerpon)
  end

  test "search treats LIKE metacharacters as literals" do
    assert_empty Archetype.search("b_dew"), "_ must not act as a wildcard"
    assert_empty Archetype.search("bud%w"), "% must not act as a wildcard"
  end
end
