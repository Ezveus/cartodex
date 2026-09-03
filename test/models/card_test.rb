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

  test "rejects a second card with the same set and number" do
    duplicate = cards(:honedge).dup

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:set_number], "has already been taken"
  end

  test "the database refuses a duplicate printing even with validations skipped" do
    duplicate = cards(:honedge).dup

    # The validation above is for the readable error; this index is the actual
    # guarantee. Cards::Fetcher looks printings up by exactly this pair, so a
    # duplicate would make that lookup arbitrary — and permanent, since a known
    # printing is never re-scraped.
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
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

  test "saving normalizes the name with full Unicode case folding" do
    card = cards(:honedge)
    card.update!(name: "Flabébé")

    assert_equal "flabébé", card.reload.name_normalized
  end

  # name_matching is the one filter behind the collection page, the admin card list and two MCP
  # tools, and it promises case-insensitivity. Matching on `name` would have delivered that for
  # ASCII only, since SQLite's LIKE folds A–Z and nothing else — hence the uppercase accented
  # letter in the stored name: a lowercase query reaches it only through name_normalized.
  test "name_matching ignores case on accented letters" do
    cards(:honedge).update!(name: "FLABÉBÉ")

    %w[FLABÉBÉ Flabébé flabébé BÉBÉ bébé].each do |query|
      assert_includes Card.name_matching(query).pluck(:name), "FLABÉBÉ", "#{query.inspect} must match"
    end
  end

  test "name_matching treats LIKE metacharacters in the query as literals" do
    assert_includes Card.name_matching("honedge").pluck(:name), "Honedge", "sanity: the plain spelling matches"
    assert_empty Card.name_matching("h_nedge"), "_ must not act as a wildcard"
    assert_empty Card.name_matching("hon%ge"), "% must not act as a wildcard"
  end

  # Fixtures are inserted without callbacks, so cards.yml spells name_normalized
  # out by hand; this is what stops the two from drifting when a name is edited.
  test "every card fixture carries the normalization its name implies" do
    Card.find_each do |card|
      assert_equal card.name.downcase, card.name_normalized, "#{card.name.inspect} fixture is out of step"
    end
  end

  # The test environment's cache store is :null_store, which makes every fetch a miss and
  # every one of these assertions vacuous. A real store has to stand in — the same pattern
  # test/controllers/cards_rate_limit_test.rb uses for `rate_limit`.
  test "filter_values is computed once and forgotten on demand" do
    with_real_cache do
      first = count_queries { Card.filter_values }
      assert_operator first, :>, 0, "expected the first call to actually query"

      assert_equal 0, count_queries { Card.filter_values }, "expected the second call to be served from cache"

      Card.forget_filter_values

      assert_equal first, count_queries { Card.filter_values }, "expected forgetting to send it back to the database"
    end
  end

  test "filter_values reports the values in the catalog" do
    with_real_cache do
      rarities, marks = Card.filter_values

      assert_equal Card.where.not(rarity: [ nil, "" ]).distinct.order(:rarity).pluck(:rarity), rarities
      assert_equal Card.where.not(regulation_mark: [ nil, "" ]).distinct.order(:regulation_mark).pluck(:regulation_mark), marks
    end
  end

  private

  def with_real_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    yield
  ensure
    Rails.cache = original
  end
end
