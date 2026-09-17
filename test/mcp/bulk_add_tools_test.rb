require "test_helper"

class BulkAddToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)            # user one
    @context = { user: @user }
  end

  def response_text(response) = response.content.first[:text]

  def refused?(response) = response.to_h[:isError]

  def entry(code, number, quantity = nil)
    { set_code: code, set_number: number }.tap { |e| e[:quantity] = quantity if quantity }
  end

  # --- the four shape refusals -------------------------------------------------------------
  # `isError` is the only field a client can read without parsing English, and text("Error: …")
  # and error_text("Error: …") are byte-identical in the text block. Asserting the flag is what
  # separates them.

  # "POR 56" and [ "POR 56" ] both answer `[]` with an Integer index, so an entry of either shape
  # made ReferenceResolver#read raise an unrescued TypeError instead of refusing. Unreachable over
  # the wire, where the schema requires objects — reachable in process, which is the door
  # McpTool#positive_quantity? already exists for.
  test "an empty, non-array or non-object entries list is refused on both tools" do
    [ [], nil, "POR 56", [ "POR 56" ], [ [ "POR", "56" ] ], [ { set_code: "POR", set_number: "56" }, 7 ] ].each do |bad|
      collection = AddCardsToCollectionTool.call(entries: bad, server_context: @context)
      assert refused?(collection), "entries #{bad.inspect} was not refused with isError"
      assert_match(/non-empty array/, response_text(collection))

      deck = AddCardsToDeckTool.call(deck_key: @deck.key, entries: bad, server_context: @context)
      assert refused?(deck), "entries #{bad.inspect} was not refused with isError on the deck tool"
    end
  end

  test "more entries than the cap are refused before anything is resolved" do
    too_many = Array.new(BulkAdd::MAX_ENTRIES + 1) { entry("POR", "56") }

    response = AddCardsToCollectionTool.call(entries: too_many, server_context: @context)

    assert refused?(response)
    assert_match(/at most #{BulkAdd::MAX_ENTRIES} entries per call \(got #{BulkAdd::MAX_ENTRIES + 1}\)/, response_text(response))
  end

  # --- all or nothing ----------------------------------------------------------------------

  # Asserting row *counts* would be satisfied by a resolve-write-then-refuse implementation:
  # Collections::CardAdder sums onto the row the fixtures already hold, so the count never moves
  # either way. The quantity is what tells them apart. The batch carries a resolvable entry
  # beside the unresolved one, or the write path is never entered at all.
  test "one unresolved entry refuses the whole call and writes nothing to the collection" do
    before = collections(:one).quantity

    response = AddCardsToCollectionTool.call(
      entries: [ entry("POR", "56", 2), entry("POR", "99999") ], server_context: @context
    )

    assert refused?(response)
    assert_equal before, collections(:one).reload.quantity, "a resolvable entry was written despite the refusal"
    assert_match(/POR 99999 — no printing in the catalogue/, response_text(response))
    assert_no_match(/POR 56/, response_text(response), "the refusal named an entry that resolved fine")
  end

  test "one unresolved entry refuses the whole call and writes nothing to the deck" do
    @deck.update!(physical: true)
    deck_cards(:one).update!(quantity: 1, owned_copies: 1)

    response = AddCardsToDeckTool.call(
      deck_key: @deck.key, entries: [ entry("POR", "56", 2), entry("ZZZZ", "1") ], server_context: @context
    )

    assert refused?(response)
    row = deck_cards(:one).reload
    assert_equal 1, row.quantity
    assert_equal 1, row.owned_copies
  end

  test "a refusal writes no Import" do
    assert_no_difference "Import.count" do
      AddCardsToCollectionTool.call(entries: [ entry("POR", "99999") ], server_context: @context)
      AddCardsToCollectionTool.call(entries: [], server_context: @context)
      AddCardsToDeckTool.call(deck_key: "nope", entries: [ entry("POR", "56") ], server_context: @context)
    end
  end

  # --- success -----------------------------------------------------------------------------

  test "repeats are summed and the collection reaches the total" do
    response = AddCardsToCollectionTool.call(
      entries: [ entry("POR", "56"), entry("POR", "56"), entry("POR", "57", 3) ], server_context: @context
    )

    assert_not refused?(response)
    assert_equal 3, @user.collections.find_by(card: cards(:honedge)).quantity   # 1 + 1 + 1
    assert_equal 3, @user.collections.find_by(card: cards(:doublade)).quantity
  end

  # The two counts are two different numbers here on purpose: a batch of N distinct entries at
  # quantity 1 makes copies == printings, so a label built from entries.size twice, or with the
  # two swapped, would satisfy any assertion made against it.
  test "the label names copies and printings, and they are not the same number" do
    AddCardsToCollectionTool.call(
      entries: [ entry("POR", "56"), entry("POR", "56"), entry("POR", "57", 3) ], server_context: @context
    )

    assert_equal "Collection — 5 copies over 2 printings", Import.last.label
  end

  test "the label is singular for one copy of one printing" do
    AddCardsToCollectionTool.call(entries: [ entry("POR", "56") ], server_context: @context)

    assert_equal "Collection — 1 copy over 1 printing", Import.last.label
  end

  test "success writes exactly one completed Import carrying the receipt" do
    assert_difference "Import.count", 1 do
      AddCardsToCollectionTool.call(
        entries: [ entry("POR", "56", 2), entry("POR", "57") ], server_context: @context
      )
    end

    import = Import.last
    assert_equal "bulk_cards", import.kind
    assert_equal "completed", import.status
    assert_equal @user, import.user

    receipt = Import.find(import.id).receipt   # re-read: the column is JSON, so the keys come back as Strings
    assert_equal 2, receipt.size
    honedge = receipt.find { |row| row["set_number"] == "56" }
    assert_equal({ "set_name" => "POR", "name" => "Honedge", "quantity" => 2, "before" => 1, "after" => 3 },
                 honedge.except("card_id", "set_number"))
  end

  test "the deck tool records the backing on both sides of the add" do
    @user.collections.find_by(card: cards(:honedge)).update!(quantity: 3)
    @deck.update!(physical: true)
    deck_cards(:one).update!(quantity: 1, owned_copies: 1)

    response = AddCardsToDeckTool.call(
      deck_key: @deck.key, entries: [ entry("POR", "56", 2) ], server_context: @context
    )

    assert_not refused?(response)
    assert_match(/1 → 3 \(1 → 3 real\)/, response_text(response))
    assert_equal "Deck “#{@deck.name}” — 2 copies over 1 printing", Import.last.label
  end

  test "the deck tool refuses another member's deck without writing" do
    other = decks(:two) # user two

    assert_no_difference [ "DeckCard.count", "Import.count" ] do
      response = AddCardsToDeckTool.call(
        deck_key: other.key, entries: [ entry("POR", "56") ], server_context: @context
      )

      assert refused?(response), "a foreign deck key was refused without isError"
      assert_match(/must belong to you/, response_text(response))
    end
  end
end
