require "test_helper"

class ImportTest < ActiveSupport::TestCase
  # A bulk card add writes one row of its own, so the kind has to be in the inclusion list before
  # anything can record one — a kind absent from KINDS fails validation rather than being ignored.
  test "bulk_cards is a kind an import may carry" do
    import = users(:one).imports.new(kind: "bulk_cards", label: "Collection — 5 copies over 3 printings")

    assert import.valid?, import.errors.full_messages.to_sentence
  end

  # Every other kind writes no receipt at all, and a reader of one must never have to nil-check
  # first — the same trade created_standing_ids makes, and the reason the column is NOT NULL with
  # an array default rather than a nullable json.
  test "an import that records no receipt reads back as an empty array, never nil" do
    import = users(:one).imports.create!(kind: "deck", label: "Raging Bolt")

    assert_equal [], import.reload.receipt
  end

  # The one rule every reader of this column has to know: `receipt` is json, so SQLite hands the
  # keys back as Strings whatever was written. A view or a response reading entry[:name] renders
  # empty against a persisted row while every "the node is present" assertion stays true, which is
  # why this asserts the Symbol read is nil rather than only that the String read works.
  test "a receipt written with Symbol keys reads back with String keys" do
    import = users(:one).imports.create!(
      kind: "bulk_cards",
      label: "Collection — 2 copies over 1 printing",
      status: "completed",
      receipt: [ { card_id: cards(:honedge).id, set_name: "POR", set_number: "56",
                   name: "Honedge", quantity: 2, before: 1, after: 3 } ]
    )

    entry = import.reload.receipt.first

    assert_equal %w[card_id set_name set_number name quantity before after].sort, entry.keys.sort
    assert_equal "Honedge", entry["name"]
    assert_nil entry[:name], "a Symbol read off a json column answers nil, silently"
  end

  # The deck shape carries two more keys than the collection shape. Both are stored in the same
  # column and read by the same view, so the difference is data rather than a second kind.
  test "a deck receipt carries the owned columns beside the rest" do
    import = users(:one).imports.create!(
      kind: "bulk_cards",
      label: "Deck \"Raging Bolt\" — 2 copies over 1 printing",
      status: "completed",
      receipt: [ { card_id: cards(:honedge).id, set_name: "POR", set_number: "56",
                   name: "Honedge", quantity: 2, before: 1, after: 3,
                   owned_before: 1, owned_after: 2 } ]
    )

    entry = import.reload.receipt.first

    assert_equal 1, entry["owned_before"]
    assert_equal 2, entry["owned_after"]
  end
end
