require "test_helper"

class LimitlessArchetypeMappingTest < ActiveSupport::TestCase
  # The two partial UNIQUE indexes, one test each, and both spelled as RecordNotUnique on a
  # validation-skipping save: a bare assert_raises here is satisfied by #reference_is_unique and
  # says nothing at all about the database. Testing only the base case ships an implementation
  # that lets a variant be mapped twice, after which .by_reference's Hash silently keeps whichever
  # row came back last.
  test "the database refuses a second mapping of one base deck" do
    LimitlessArchetypeMapping.create!(limitless_deck_id: 900, label: "Dragapult",
      archetype: archetypes(:ogerpon))
    twin = LimitlessArchetypeMapping.new(limitless_deck_id: 900, label: "Dragapult",
      archetype: archetypes(:budew_ogerpon))

    assert_raises(ActiveRecord::RecordNotUnique) { twin.save!(validate: false) }
  end

  # SQLite treats NULLs as distinct, so the composite index alone never sees the base case above —
  # which is why there are two indexes and why this one has to be asserted separately rather than
  # assumed to follow.
  test "the database refuses a second mapping of one variant" do
    LimitlessArchetypeMapping.create!(limitless_deck_id: 900, limitless_variant: 3,
      label: "Dragapult Dusknoir", archetype: archetypes(:ogerpon))
    twin = LimitlessArchetypeMapping.new(limitless_deck_id: 900, limitless_variant: 3,
      label: "Dragapult Dusknoir", archetype: archetypes(:budew_ogerpon))

    assert_raises(ActiveRecord::RecordNotUnique) { twin.save!(validate: false) }
  end

  # The base deck and its variant are two decks, not one deck seen twice: 284 is Dragapult and
  # 284/3 is Dragapult Dusknoir. Keyed on the base id alone, four real decks become one.
  test "a base deck and a variant of it are two mappings" do
    assert_equal "284", limitless_archetype_mappings(:dragapult).reference
    assert_equal "284/3", limitless_archetype_mappings(:dragapult_dusknoir).reference
  end

  # The plan resolves a whole run's references in one query, so the lookup has to answer the base
  # and the variant halves of one deck id together and must not let either answer for the other.
  test "by_reference answers the references it was asked for and no others" do
    found = LimitlessArchetypeMapping.by_reference([ "284", "284/3", "401/2", "999" ])

    assert_equal %w[284 284/3 401/2], found.keys.sort
    assert_equal archetypes(:ogerpon), found["284"].archetype
    assert_equal archetypes(:budew_ogerpon), found["284/3"].archetype
  end

  # 284 must never answer for 284/9: a variant nobody has confirmed is a refusal, and answering it
  # with the base deck's archetype is exactly the silent guess this store exists to prevent.
  test "by_reference answers nothing for an unconfirmed variant of a mapped deck" do
    assert_empty LimitlessArchetypeMapping.by_reference([ "284/9" ])
  end

  test "parse_reference reads both shapes and refuses anything else" do
    assert_equal [ 284, nil ], LimitlessArchetypeMapping.parse_reference("284")
    assert_equal [ 284, 3 ], LimitlessArchetypeMapping.parse_reference("284/3")
    assert_nil LimitlessArchetypeMapping.parse_reference("284/3/9")
    assert_nil LimitlessArchetypeMapping.parse_reference(nil)
  end

  # The two index tests deliberately use save!(validate: false), so they prove the database and say
  # nothing about the model. Commenting out `validate :reference_is_unique` left the whole suite
  # green — and the validation is what produces a readable error on the admin form instead of a
  # RecordNotUnique 500, the same division of labour Card and Tournament keep.
  test "the model refuses a duplicate before the database has to" do
    LimitlessArchetypeMapping.create!(limitless_deck_id: 901, label: "Dragapult", archetype: archetypes(:ogerpon))

    duplicate = LimitlessArchetypeMapping.new(limitless_deck_id: 901, label: "Dragapult again",
      archetype: archetypes(:budew_ogerpon))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:limitless_deck_id], "is already mapped"
  end

  test "the model refuses a duplicate variant before the database has to" do
    LimitlessArchetypeMapping.create!(limitless_deck_id: 902, limitless_variant: 4, label: "A",
      archetype: archetypes(:ogerpon))

    duplicate = LimitlessArchetypeMapping.new(limitless_deck_id: 902, limitless_variant: 4, label: "B",
      archetype: archetypes(:ogerpon))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:limitless_deck_id], "is already mapped"
  end
end
