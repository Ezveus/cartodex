require "test_helper"

module Collections
  class VariantMoverTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge) # card_set :por — region "international", so fr is legal
      @source = @user.collections.find_by!(card: @card)
      @source.update!(quantity: 4)
    end

    def move(quantity: 1, to_language: "fr", to_finish: "unknown", from_language: "unknown", from_finish: "unknown")
      Collections::VariantMover.call(
        user: @user, card: @card, quantity: quantity,
        from_language: from_language, from_finish: from_finish,
        to_language: to_language, to_finish: to_finish
      )
    end

    test "splits copies into a variant that did not exist yet" do
      result = move(quantity: 1)

      assert_equal 3, result.source.reload.quantity
      assert_equal 1, result.target.quantity
      assert_equal "fr", result.target.language
      assert_not result.merged
      assert_not result.source_removed
    end

    # The reason this is one service and not a QuantitySetter followed by a
    # CardAdder: those two writes would dip the owned total between them, and
    # since Σ owned_copies ≤ owned is surfaced rather than enforced, a concurrent
    # reader would see an over-allocation that never existed.
    test "leaves the owned total unchanged" do
      before = @user.collections.where(card: @card).sum(:quantity)

      move(quantity: 2)

      assert_equal before, @user.collections.where(card: @card).sum(:quantity)
    end

    test "merges into a target variant that already exists" do
      @user.collections.create!(card: @card, quantity: 2, language: "fr")

      result = move(quantity: 1)

      assert result.merged
      assert_equal 3, result.target.quantity
      assert_equal 1, @user.collections.where(card: @card, language: "fr").count
    end

    # An empty variant row records nothing while occupying a slot in the unique
    # index and a tile in the grid to say "zero French copies", which absence
    # already says. QuantitySetter's zero rows are a different case: they are the
    # user asking for that printing to read zero.
    test "destroys the source when the move empties it" do
      result = move(quantity: 4)

      assert result.source_removed
      assert_nil @user.collections.find_by(card: @card, language: "unknown", finish: "unknown")
      assert_equal 4, @user.collections.find_by!(card: @card, language: "fr").quantity
    end

    test "moves between finishes of one language" do
      result = move(quantity: 2, to_language: "unknown", to_finish: "reverse_holo")

      assert_equal 2, result.target.quantity
      assert_equal "reverse_holo", result.target.finish
      assert_equal 2, result.source.reload.quantity
    end

    test "refuses to move more copies than the source holds" do
      error = assert_raises(ArgumentError) { move(quantity: 5) }

      assert_match(/only 4/, error.message)
      assert_equal 4, @source.reload.quantity, "the failed move must leave the source untouched"
    end

    test "refuses a non-positive quantity" do
      assert_raises(ArgumentError) { move(quantity: 0) }
      assert_raises(ArgumentError) { move(quantity: -1) }
    end

    test "refuses a move to the variant it starts from" do
      assert_raises(ArgumentError) { move(quantity: 1, to_language: "unknown", to_finish: "unknown") }
    end

    test "raises when the source variant does not exist" do
      assert_raises(ActiveRecord::RecordNotFound) do
        move(quantity: 1, from_language: "de", to_language: "fr")
      end
    end

    test "refuses a target language the card's set is not printed in" do
      assert_raises(ActiveRecord::RecordInvalid) { move(quantity: 1, to_language: "ja") }
      assert_equal 4, @source.reload.quantity, "the rejected move must not have decremented the source"
    end
  end
end
