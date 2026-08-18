require "test_helper"

class CardSetTest < ActiveSupport::TestCase
  test "region defaults to international" do
    set = CardSet.create!(code: "TST", name: "Test Set")

    assert_equal "international", set.region
  end

  test "rejects a region that is not a known print run" do
    set = CardSet.new(code: "TST", name: "Test Set", region: "atlantis")

    assert_not set.valid?
    assert_includes set.errors[:region], "is not included in the list"
  end

  test "allowed_languages derives from the region" do
    assert_equal %w[en fr de es it pt], CardSet.new(region: "international").allowed_languages
    assert_equal %w[ja], CardSet.new(region: "japan").allowed_languages
    assert_equal %w[zh-Hant], CardSet.new(region: "taiwan").allowed_languages
  end

  # allowed_languages hands the caller the constant's own array, and stage 2 will
  # feed it straight into a language <select>. A << or sort! there would corrupt
  # the validation vocabulary for the rest of the process.
  test "the language lists cannot be mutated through allowed_languages" do
    assert_raises(FrozenError) { CardSet.new(region: "japan").allowed_languages << "xx" }
  end

  # Limitless disambiguates its two trees by path, not by code (/cards/SVI against
  # /cards/jp/M6), and codes do collide: XY7 is a Japanese set and the XY era has
  # international codes too.
  test "the same code coexists in two regions" do
    CardSet.create!(code: "XY7", name: "Ancient Origins")

    japanese = CardSet.new(code: "XY7", name: "Bandit Ring", region: "japan")

    assert japanese.valid?, japanese.errors.full_messages.to_sentence
    assert japanese.save
  end

  test "the same code is rejected within one region" do
    CardSet.create!(code: "XY7", name: "Ancient Origins")

    duplicate = CardSet.new(code: "XY7", name: "Ancient Origins, again")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:code], "has already been taken"
  end

  # The index, not the validation. A model-only test would pass against the old
  # global unique index and tell us nothing about the one that has to widen.
  test "the database itself scopes code uniqueness to the region" do
    CardSet.create!(code: "XY7", name: "Ancient Origins")
    CardSet.new(code: "XY7", name: "Bandit Ring", region: "japan").save!(validate: false)

    assert_raises(ActiveRecord::RecordNotUnique) do
      CardSet.new(code: "XY7", name: "Bandit Ring, again", region: "japan").save!(validate: false)
    end
  end
end
