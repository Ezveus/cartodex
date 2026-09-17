require "test_helper"

class Collections::BulkCardAdderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)              # owns honedge ×1, budew_pre ×0, budew_asc ×0
    @honedge = cards(:honedge)       # POR 56
    @doublade = cards(:doublade)     # POR 57, not in this user's collection
  end

  def resolved(*pairs)
    pairs.map { |card, quantity| { card: card, quantity: quantity } }
  end

  test "sums onto an existing row and creates a missing one in one call" do
    receipt = Collections::BulkCardAdder.call(user: @user, resolved: resolved([ @honedge, 2 ], [ @doublade, 3 ]))

    assert_equal 3, @user.collections.find_by(card: @honedge).quantity
    assert_equal 3, @user.collections.find_by(card: @doublade).quantity
    assert_equal 2, receipt.size
  end

  # collections is UNIQUE on (user_id, card_id, language, finish), so a writer that spelled either
  # of those differently would not fail — it would quietly open a second row and split the owned
  # count in two. The fixture rows carry the schema defaults, so a second row is what any other
  # value produces.
  test "writes the unknown language and finish, never a second row for one printing" do
    assert_no_difference -> { @user.collections.where(card: @honedge).count } do
      Collections::BulkCardAdder.call(user: @user, resolved: resolved([ @honedge, 1 ]))
    end

    row = @user.collections.find_by(card: @honedge)
    assert_equal "unknown", row.language
    assert_equal "unknown", row.finish
  end

  # Read back off a *reloaded* Import-shaped payload with String keys: the receipt's destination is
  # a `json` column, which hands its keys back as Strings whatever was written, so a receipt built
  # with Symbol keys would satisfy every "length == N" assertion and render empty everywhere.
  test "the receipt carries String keys and before/after that match the database" do
    receipt = Collections::BulkCardAdder.call(user: @user, resolved: resolved([ @honedge, 2 ], [ @doublade, 3 ]))
    round_tripped = JSON.parse(receipt.to_json)

    assert_equal receipt, round_tripped, "receipt keys did not survive the JSON round trip"

    honedge_entry = round_tripped.find { |entry| entry["card_id"] == @honedge.id }
    assert_equal({ "set_name" => "POR", "set_number" => "56", "name" => "Honedge",
                   "quantity" => 2, "before" => 1, "after" => 3 },
                 honedge_entry.except("card_id"))
    assert_equal 3, @user.collections.find_by(card: @honedge).quantity

    doublade_entry = round_tripped.find { |entry| entry["card_id"] == @doublade.id }
    assert_equal 0, doublade_entry["before"], "a printing the user did not own must start at 0"
    assert_equal 3, doublade_entry["after"]
  end

  test "a row that cannot be saved rolls the whole batch back" do
    assert_no_difference -> { @user.collections.sum(:quantity) } do
      assert_raises(ActiveRecord::ActiveRecordError) do
        Collections::BulkCardAdder.call(user: @user, resolved: resolved([ @honedge, 2 ], [ Card.new, 1 ]))
      end
    end

    assert_equal 1, @user.collections.find_by(card: @honedge).quantity
  end

  # The literal, not "the two counts agree": the per-row write is legitimately not flat, so a
  # comparison of totals is satisfied by a per-row pre-read as readily as by a batched one. What is
  # pinned is the pre-read statement itself — one, whatever the batch size. `uncached` because the
  # query cache answers a repeated identical read and SQLCounter skips a CACHE event, so an
  # unbatched version can measure as a batched one.
  PRE_READ = /SELECT "collections"\."card_id", "collections"\."quantity"/

  test "the before-quantities are read in exactly one statement, whatever the batch size" do
    one = capture_queries do
      ActiveRecord::Base.uncached { Collections::BulkCardAdder.call(user: @user, resolved: resolved([ @honedge, 1 ])) }
    end
    assert_equal 1, one.grep(PRE_READ).size

    many = resolved(*Array.new(20) { |n| [ minted_card(n), 1 ] })
    twenty = capture_queries do
      ActiveRecord::Base.uncached { Collections::BulkCardAdder.call(user: @user, resolved: many) }
    end
    assert_equal 1, twenty.grep(PRE_READ).size,
      "the pre-read ran #{twenty.grep(PRE_READ).size} times for 20 printings; it is no longer batched"
  end

  private

  def minted_card(number)
    Card.create!(name: "Bulk Probe #{number}", card_type: "Trainer", set_name: "ZZY",
                 set_number: number.to_s, rarity: "Common")
  end
end
