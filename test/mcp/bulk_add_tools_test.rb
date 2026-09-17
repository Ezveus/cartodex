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

  # The literal, because the constant is the policy and every other assertion in this file reads it
  # back. It was 500 until the write lock was measured: 500 entries hold SQLite's single write lock
  # 1.2-4.0 s, four concurrent calls exhaust database.yml's 5 s timeout, and a member clicking + on
  # a card page waited 2.98 s behind six of them. 120 is ~0.35 s and twice the largest real payload.
  test "the cap is 120 entries" do
    assert_equal 120, BulkAdd::MAX_ENTRIES
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

  # Both tools claim in a comment that the cards and the Import commit together — "an Import that
  # named copies nobody has, or copies with no Import naming them, are both worse than neither".
  # Measured: moving record_import outside the transaction left every other test in this file, in
  # import_test.rb, in the collection adder's tests and in mcp_server_test.rb green. The claim
  # needed a case where the two halves can diverge, which is a failing Import over cards that have
  # already been written.
  #
  # define_singleton_method rather than a stub: minitest 6 dropped minitest/mock out of the gem and
  # it is not in this bundle, so Object#stub does not exist here.
  def with_failing_import(tool)
    tool.define_singleton_method(:record_import) { |**| raise ActiveRecord::RecordInvalid, Import.new }
    yield
  ensure
    tool.singleton_class.send(:remove_method, :record_import)
  end

  test "a failing Import write takes the collection rows with it" do
    before = collections(:one).quantity

    response = assert_no_difference "Import.count" do
      with_failing_import(AddCardsToCollectionTool) do
        AddCardsToCollectionTool.call(entries: [ entry("POR", "56", 2) ], server_context: @context)
      end
    end

    assert refused?(response)
    assert_equal before, collections(:one).reload.quantity,
      "the cards were committed without the Import that records them"
  end

  test "a failing Import write takes the deck rows with it" do
    @deck.update!(physical: true)
    deck_cards(:one).update!(quantity: 1, owned_copies: 1)

    response = assert_no_difference "Import.count" do
      with_failing_import(AddCardsToDeckTool) do
        AddCardsToDeckTool.call(deck_key: @deck.key, entries: [ entry("POR", "57", 2) ], server_context: @context)
      end
    end

    assert refused?(response)
    assert_equal 1, @deck.deck_cards.count, "a deck row was committed without the Import that records it"
  end

  # 9223372036854775807 passes the schema's `type: "integer"` and then overflows the column. It used
  # to reach the client as a bare JSON-RPC internal error carrying no isError at all.
  test "a quantity too large for the column is refused rather than raised" do
    before = collections(:one).quantity

    response = AddCardsToCollectionTool.call(
      entries: [ entry("POR", "56", 9_223_372_036_854_775_807) ], server_context: @context
    )

    assert refused?(response)
    assert_match(/larger than the database can hold/, response_text(response))
    assert_equal before, collections(:one).reload.quantity
  end

  # SQLite has one write lock and `database.yml` gives it a 5 s timeout; four concurrent max-size
  # calls exhaust it, measured. Unrescued this reaches the client as a JSON-RPC internal error —
  # and it is the one failure where "nothing was written" is provable rather than merely likely,
  # since the lock is taken by BEGIN IMMEDIATE before the first row, so it is also the one the
  # caller most needs told.
  test "a lock-wait timeout is refused, and says that resending is safe" do
    before = collections(:one).quantity

    Collections::BulkCardAdder.define_singleton_method(:call) do |**|
      raise ActiveRecord::StatementTimeout, "SQLite3::BusyException: database is locked"
    end
    begin
      response = AddCardsToCollectionTool.call(entries: [ entry("POR", "56", 2) ], server_context: @context)
    ensure
      Collections::BulkCardAdder.singleton_class.send(:remove_method, :call)
    end

    assert refused?(response), "a busy database was not reported with isError"
    assert_match(/nothing was written/, response_text(response))
    assert_match(/again is safe/, response_text(response))
    assert_equal before, collections(:one).reload.quantity
  end

  # The rule CLAUDE.md states for Decks::Fetcher, applied here: every printing is resolved *before*
  # the write transaction opens, because SQLite has one write lock and Cards::Fetcher costs ~0.7 s
  # per unknown printing. StandingsImporterTest pins the same promise by recording transaction depth,
  # and this does too — it is the only thing that would notice the day somebody moves the resolve
  # inside `transaction do`, or gives the resolver a fetch fallback.
  #
  # Depth rather than "BEGIN IMMEDIATE was issued": fixtures pin the connection with a non-joinable
  # transaction, which the adapter begins *deferred*, so under test the tools' own transaction is a
  # savepoint and the immediate BEGIN is never observable at all.
  test "the references are resolved before the write transaction opens" do
    baseline = ActiveRecord::Base.connection.open_transactions
    depths = []
    original = Cards::ReferenceResolver.method(:call)
    Cards::ReferenceResolver.define_singleton_method(:call) do |**kwargs|
      depths << ActiveRecord::Base.connection.open_transactions
      original.call(**kwargs)
    end

    begin
      AddCardsToCollectionTool.call(entries: [ entry("POR", "56") ], server_context: @context)
      AddCardsToDeckTool.call(deck_key: @deck.key, entries: [ entry("POR", "57") ], server_context: @context)
    ensure
      Cards::ReferenceResolver.singleton_class.send(:remove_method, :call)
    end

    assert_equal [ baseline, baseline ], depths,
      "a printing was resolved with the write transaction already open"
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
