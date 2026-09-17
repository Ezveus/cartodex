module Collections
  # Adds many printings to one user's collection in a single transaction, and returns the receipt
  # the Import row and the MCP response are both built from.
  #
  # `resolved` is what Cards::ReferenceResolver hands back: [ { card:, quantity: } ], one row per
  # distinct printing, already summed. This service never resolves anything itself and never
  # fetches — a printing the catalogue does not hold never reaches it.
  #
  # Every row goes through Collections::CardAdder rather than writing the collection directly, so
  # the "unknown"/"unknown" language and finish defaults stay written in exactly one place. That is
  # not tidiness: `collections` is UNIQUE on (user_id, card_id, language, finish), so a second
  # spelling of those two would silently split one printing's owned count across two rows.
  class BulkCardAdder < ApplicationService
    def initialize(user:, resolved:)
      @user = user
      @resolved = resolved
    end

    def call
      serialized_transaction do
        before = quantities_before
        @resolved.map do |row|
          card = row[:card]
          collection = CardAdder.call(user: @user, card: card, quantity: row[:quantity])
          entry(card, row[:quantity], before.fetch(card.id, 0), collection.quantity.to_i)
        end
      end
    end

    private

    # One grouped read for the whole batch, before any write. Read per row instead and the receipt
    # would still be right, but at a query per printing — 52 of them for one booster box.
    def quantities_before
      @user.collections
           .where(card_id: @resolved.map { |row| row[:card].id }, language: "unknown", finish: "unknown")
           .pluck(:card_id, :quantity)
           .to_h { |card_id, quantity| [ card_id, quantity.to_i ] }
    end

    # String keys, because this is written straight into a `json` column and read back out of one:
    # a row re-read from the database hands its keys back as Strings whatever was written, so a
    # reader spelling them as Symbols renders empty against every persisted row while staying true
    # of the one still in memory.
    def entry(card, quantity, before, after)
      {
        "card_id" => card.id, "set_name" => card.set_name, "set_number" => card.set_number,
        "name" => card.name, "quantity" => quantity, "before" => before, "after" => after
      }
    end
  end
end
