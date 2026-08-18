require "test_helper"

class CollectionTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @international = cards(:honedge)  # card_set :por — region "international"
    @setless = cards(:trainer_card)   # Card belongs_to :card_set is optional
  end

  test "language and finish default to the unknown sentinel" do
    collection = @user.collections.create!(card: @international, quantity: 1)

    assert_equal "unknown", collection.language
    assert_equal "unknown", collection.finish
  end

  test "accepts a finish from the list" do
    collection = @user.collections.new(card: @international, quantity: 1, finish: "poke_ball_reverse")

    assert collection.valid?, collection.errors.full_messages.to_sentence
  end

  # A typo would fork a row in silence and make the user believe they own 1 + 1
  # instead of 2 — the exact failure this feature exists to remove.
  test "rejects a finish outside the list" do
    collection = @user.collections.new(card: @international, quantity: 1, finish: "sparkly")

    assert_not collection.valid?
    assert_includes collection.errors[:finish], "is not included in the list"
  end

  test "holo is not a finish: it is a rarity, and lives on the card" do
    assert_not_includes Collection::FINISHES, "holo"
  end

  test "accepts a language the card's set is printed in" do
    collection = @user.collections.new(card: @international, quantity: 1, language: "fr")

    assert collection.valid?, collection.errors.full_messages.to_sentence
  end

  test "rejects a language the card's set is not printed in" do
    collection = @user.collections.new(card: @international, quantity: 1, language: "ja")

    assert_not collection.valid?
    assert_includes collection.errors[:language], "is not printed for this set"
  end

  test "a Japanese set takes ja and refuses fr" do
    japanese_set = CardSet.create!(code: "M6", name: "Mega Symphonia", region: "japan")
    card = Card.create!(
      name: "Budew", card_type: "Pokémon", hp: 30, stage: "Basic", type_symbol: "Grass",
      retreat_cost: 1, set_name: "M6", set_number: "4", rarity: "Common", card_set: japanese_set
    )

    assert @user.collections.new(card: card, quantity: 1, language: "ja").valid?
    assert_not @user.collections.new(card: card, quantity: 1, language: "fr").valid?
  end

  test "unknown is accepted whatever the set" do
    collection = @user.collections.new(card: @international, quantity: 1, language: "unknown")

    assert collection.valid?, collection.errors.full_messages.to_sentence
  end

  test "a card with no set falls back to the union of every region's languages" do
    assert_nil @setless.card_set, "sanity: this fixture is the setless case"

    assert @user.collections.new(card: @setless, quantity: 1, language: "ja").valid?
    assert_not @user.collections.new(card: @setless, quantity: 1, language: "klingon").valid?
  end

  test "one printing can be owned in two variants" do
    @user.collections.create!(card: @international, quantity: 3)

    french = @user.collections.new(card: @international, quantity: 1, language: "fr")

    assert french.valid?, french.errors.full_messages.to_sentence
    assert french.save
  end

  test "the same printing in the same variant is rejected" do
    @user.collections.create!(card: @international, quantity: 3, language: "fr", finish: "reverse_holo")

    duplicate = @user.collections.new(card: @international, quantity: 1, language: "fr", finish: "reverse_holo")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "already has this printing in this variant"
  end

  # The index, not the validation: a model-only test would pass against the old
  # (user_id, card_id) index and say nothing about the one that widened.
  test "the database itself refuses a second row for one printing in one variant" do
    @user.collections.create!(card: @international, quantity: 1)

    assert_raises(ActiveRecord::RecordNotUnique) do
      @user.collections.new(card: @international, quantity: 1).save!(validate: false)
    end
  end

  test "the database accepts two rows for one printing in different variants" do
    @user.collections.create!(card: @international, quantity: 1)

    assert_nothing_raised do
      @user.collections.new(card: @international, quantity: 1, language: "fr").save!(validate: false)
    end
  end

  # This is what makes the sentinel an invariant rather than a convention, and
  # the uniqueness test above cannot say it: that one inserts a row taking the
  # column default, so it exercises the index and would stay green with both
  # columns nullable. SQLite treats two NULLs as distinct in a unique index, so
  # nullable columns would let (user, card, NULL, NULL) insert twice and the
  # widened uniqueness would protect nothing.
  test "the database refuses a NULL variant on either column" do
    collection = @user.collections.create!(card: @international, quantity: 1)

    assert_raises(ActiveRecord::NotNullViolation) { collection.update_column(:language, nil) }
    assert_raises(ActiveRecord::NotNullViolation) { collection.update_column(:finish, nil) }
  end
end
