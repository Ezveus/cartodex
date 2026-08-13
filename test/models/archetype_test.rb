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

  # The stored name carries an uppercase accented letter on purpose: SQLite's LIKE folds F/f but
  # not É/é, so a lowercase query can only match through name_normalized. Were this scope to read
  # the plain `name` columns again, these two tests would go red — that's what they exist for.
  test "search ignores case on accented letters in the archetype name" do
    archetype = archetypes(:ogerpon)
    archetype.update!(name: "FLABÉBÉ Box", custom_name: "1")

    %w[FLABÉBÉ Flabébé flabébé].each do |query|
      assert_includes Archetype.search(query), archetype, "#{query.inspect} must match"
    end
  end

  test "search ignores case on accented letters in a member Pokémon's name" do
    cards(:budew_pre).update!(name: "FLABÉBÉ")

    %w[FLABÉBÉ Flabébé flabébé].each do |query|
      assert_includes Archetype.search(query), archetypes(:budew_ogerpon), "#{query.inspect} must match"
    end
  end

  test "every archetype fixture carries the normalization its name implies" do
    Archetype.find_each do |archetype|
      assert_equal archetype.name.downcase, archetype.name_normalized,
        "#{archetype.name.inspect} fixture is out of step"
    end
  end
end
