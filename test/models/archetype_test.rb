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

  # Drift protection for the third column of the scope: name_normalized is read off
  # secondary_cards_archetypes (the join alias), not primary_cards_archetypes or
  # archetypes itself. Both the archetype's own name and the primary Pokémon's name are renamed
  # away from the query so a match can only come through the secondary Pokémon's column. The
  # secondary is swapped to a card no other archetype fixture references (teal_mask_ogerpon_ex is
  # also archetypes(:ogerpon)'s primary — renaming it would make that fixture match too).
  test "search matches on the secondary Pokémon's name" do
    archetype = archetypes(:budew_ogerpon)
    secondary = cards(:froakie_cri)
    archetype.update!(secondary_card: secondary, name: "Mystery Box", custom_name: "1")
    secondary.update!(name: "Flittle")

    assert_includes Archetype.search("Flittle"), archetype

    archetype.update!(secondary_card: nil, custom_name: "1")
    assert_empty Archetype.search("Flittle"),
      "must not match without the secondary Pokémon: the archetype's own name and the primary's are both unrelated to the query"
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

  # The `search` scope spells its second join alias by hand, and Rails derives
  # that alias from the association name — so renaming the association breaks
  # the scope at query time, not at load time. These two run the SQL.
  test "search runs against the renamed associations" do
    assert_respond_to archetypes(:ogerpon), :primary_card
    assert_respond_to archetypes(:ogerpon), :secondary_card
    assert_nothing_raised { Archetype.search("Ogerpon").to_a }
  end
end
