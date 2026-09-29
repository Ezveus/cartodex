require "test_helper"

class DeckVersionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Versioned", standard_pool: standard_pools(:twm_por))
  end

  test "a version's number is its rank by effective_at within its deck" do
    later = build_version(effective_at: 2.days.ago)
    assert_equal 1, later.number

    # "Add an earlier version": inserted before the existing one, so both renumber.
    earlier = build_version(effective_at: 5.days.ago)

    assert_equal 1, earlier.number
    assert_equal 2, later.reload.number
    assert_equal [ earlier.id, later.id ], @deck.ordered_versions.map(&:id)
    assert_equal [ 1, 2 ], @deck.ordered_versions.map(&:number)
  end

  test "two versions sharing an effective_at are ordered by id" do
    at = 3.days.ago
    first = build_version(effective_at: at)
    second = build_version(effective_at: at)

    assert_equal [ 1, 2 ], [ first.number, second.number ]
    assert_equal [ first.id, second.id ], @deck.ordered_versions.map(&:id)
  end

  test "another deck's earlier version does not shift this deck's numbers" do
    mine = build_version(effective_at: 2.days.ago)
    other_deck = @user.decks.create!(name: "Other", standard_pool: standard_pools(:twm_por))
    DeckVersion.create!(deck: other_deck, effective_at: 10.days.ago, format: "standard",
      standard_pool: standard_pools(:twm_por))

    assert_equal 1, mine.number
    assert_equal [ 1 ], @deck.ordered_versions.map(&:number)
  end

  test "a written number wins over the computed rank" do
    version = build_version(effective_at: 2.days.ago)
    version.number = 7

    assert_equal 7, version.number
    assert_equal "v7", version.label
    assert_equal "v7", version.name
  end

  test "latest_version is the last by effective_at, whatever the insertion order" do
    later = build_version(effective_at: 1.day.ago)
    build_version(effective_at: 5.days.ago)

    assert_equal later, @deck.latest_version
  end

  test "deck_cards answers the version's own cards, for Decks::Comparator" do
    version = build_version(effective_at: 1.day.ago)
    version.deck_version_cards.create!(card: cards(:honedge), quantity: 3)

    assert_equal [ [ cards(:honedge), 3 ] ], version.deck_cards.map { |row| [ row.card, row.quantity ] }
  end

  test "effective_at is required and may not be in the future" do
    version = @deck.deck_versions.build(format: "standard", standard_pool: standard_pools(:twm_por))
    assert_not version.valid?
    assert_includes version.errors[:effective_at], "can't be blank"

    version.effective_at = 1.day.from_now
    assert_not version.valid?
    assert_includes version.errors[:effective_at], "can't be in the future"
  end

  test "the format rules are the deck's" do
    standard = @deck.deck_versions.build(effective_at: 1.day.ago, format: "standard")
    assert_not standard.valid?
    assert_includes standard.errors[:standard_pool], "can't be blank"

    other = @deck.deck_versions.build(effective_at: 1.day.ago, format: "other")
    assert_not other.valid?
    assert_includes other.errors[:other_format_name], "can't be blank"

    bogus = @deck.deck_versions.build(effective_at: 1.day.ago, format: "bogus")
    assert_not bogus.valid?
    assert_includes bogus.errors[:format], "is not included in the list"

    expanded = @deck.deck_versions.build(effective_at: 1.day.ago, format: "expanded",
      standard_pool: standard_pools(:twm_por), other_format_name: "stale")
    assert expanded.valid?, expanded.errors.full_messages.to_sentence
    assert_nil expanded.standard_pool_id
    assert_nil expanded.other_format_name
  end

  test "format_label speaks the deck's wording" do
    version = build_version(effective_at: 1.day.ago)
    assert_equal @deck.format_label, version.format_label
    assert_equal "Standard (#{standard_pools(:twm_por).name})", version.format_label

    unnamed = DeckVersion.new(format: "other")
    assert_equal "Other", unnamed.format_label

    named = DeckVersion.new(format: "other", other_format_name: "Gym Leader Challenge")
    assert_equal "Gym Leader Challenge", named.format_label
  end

  test "a card quantity must be positive" do
    version = build_version(effective_at: 1.day.ago)
    row = version.deck_version_cards.build(card: cards(:honedge), quantity: 0)

    assert_not row.valid?
    assert_includes row.errors[:quantity], "must be greater than 0"
  end

  test "a version with a result or an entry refuses to be destroyed" do
    version = build_version(effective_at: 1.day.ago)
    @deck.deck_results.create!(result: "win", deck_version: version)

    assert_not version.destroy
    assert DeckVersion.exists?(version.id)
  end

  test "an empty version is destroyed with its cards" do
    version = build_version(effective_at: 1.day.ago)
    version.deck_version_cards.create!(card: cards(:honedge), quantity: 2)

    assert_difference -> { DeckVersionCard.count }, -1 do
      assert version.destroy
    end
  end

  # Declaration order on Deck: the results go first, so the version they point at is free to go.
  test "destroying a deck removes its results and then its versions" do
    version = build_version(effective_at: 1.day.ago)
    version.deck_version_cards.create!(card: cards(:honedge), quantity: 2)
    @deck.deck_results.create!(result: "win", deck_version: version)

    assert @deck.destroy
    assert_not DeckVersion.exists?(version.id)
  end

  # --- the migration's backfill -----------------------------------------------------------
  #
  # CI loads the schema and never runs a migration, so the backfill is exercised here, against
  # rows the test builds in the pre-migration shape: the NOT NULL is lifted for the length of
  # the test, and the suite's transactional fixtures roll the DDL back.

  test "the backfill snapshots a deck with results and points them at it" do
    load_backfill
    deck = @user.decks.create!(name: "Played", standard_pool: standard_pools(:twm_por))
    travel_to(10.days.ago) { deck.deck_cards.create!(card: cards(:honedge), quantity: 3) }
    card_edited_at = deck.deck_cards.first.updated_at
    deck.update_columns(created_at: 20.days.ago)
    result = insert_result(deck)

    CreateDeckVersions.new.backfill

    version = deck.deck_versions.sole
    assert_in_delta card_edited_at, version.effective_at, 1.second
    assert_equal "standard", version.format
    assert_equal standard_pools(:twm_por).id, version.standard_pool_id
    assert_equal [ [ cards(:honedge).id, 3 ] ], version.deck_version_cards.pluck(:card_id, :quantity)
    assert_equal version.id, result.reload.deck_version_id
  end

  # SQLite's two-argument MAX is NULL as soon as one side is, so a deck with no card would
  # otherwise get a NULL effective_at and abort the NOT NULL insert.
  test "the backfill dates a deck with results and no cards from its creation" do
    load_backfill
    deck = @user.decks.create!(name: "Empty", standard_pool: standard_pools(:twm_por))
    deck.update_columns(created_at: 20.days.ago)
    insert_result(deck)

    CreateDeckVersions.new.backfill

    version = deck.deck_versions.sole
    assert_in_delta 20.days.ago, version.effective_at, 1.minute
    assert_empty version.deck_version_cards
  end

  test "the backfill snapshots a deck with only an entry" do
    load_backfill
    deck = @user.decks.create!(name: "Entered", standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:doublade), quantity: 2)
    entry_id = insert_entry(deck)

    CreateDeckVersions.new.backfill

    version = deck.deck_versions.sole
    assert_equal version.id, TournamentEntry.find(entry_id).deck_version_id
  end

  test "the backfill leaves a deck with neither results nor entries alone" do
    load_backfill
    deck = @user.decks.create!(name: "Untouched", standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:doublade), quantity: 2)

    assert_no_difference -> { DeckVersion.count } do
      CreateDeckVersions.new.backfill
    end
    assert_empty deck.deck_versions
  end

  # Only decks with no version yet are touched, and the rows the run creates are told apart from
  # older ones by id. A deck already holding a version keeps it alone and uncopied, and a row of
  # it with no version is not quietly filed on that older version — it is left for the NOT NULL
  # to refuse, loudly, rather than guessed at.
  test "the backfill leaves a deck already holding a version alone" do
    load_backfill
    held = decks(:one)
    held_cards = deck_versions(:one).deck_version_cards.pluck(:card_id, :quantity)
    stray = insert_result(held)
    fresh = @user.decks.create!(name: "Fresh", standard_pool: standard_pools(:twm_por))
    fresh.deck_cards.create!(card: cards(:honedge), quantity: 1)
    fresh_result = insert_result(fresh)

    CreateDeckVersions.new.backfill

    assert_equal [ deck_versions(:one) ], held.deck_versions.reload.to_a
    assert_equal held_cards, deck_versions(:one).deck_version_cards.reload.pluck(:card_id, :quantity)
    assert_nil stray.reload.deck_version_id
    assert_equal fresh.deck_versions.sole.id, fresh_result.reload.deck_version_id
  end

  private

  def build_version(effective_at:)
    DeckVersion.create!(deck: @deck, effective_at: effective_at, format: "standard",
      standard_pool: standard_pools(:twm_por))
  end

  def load_backfill
    require Rails.root.join("db/migrate/#{Dir.children(Rails.root.join('db/migrate')).find { |f| f.end_with?('_create_deck_versions.rb') }}")

    connection = ActiveRecord::Base.connection
    connection.change_column_null :deck_results, :deck_version_id, true
    connection.change_column_null :tournament_entries, :deck_version_id, true
  end

  def insert_result(deck)
    id = DeckResult.insert_all!([ { deck_id: deck.id, result: "win", match_format: "bo1",
      played_at: Time.current, created_at: Time.current, updated_at: Time.current } ],
      returning: [ :id ]).rows.first.first
    DeckResult.find(id)
  end

  def insert_entry(deck)
    TournamentEntry.insert_all!([ { user_id: @user.id, tournament_id: tournaments(:two).id, deck_id: deck.id,
      created_at: Time.current, updated_at: Time.current } ], returning: [ :id ]).rows.first.first
  end
end
