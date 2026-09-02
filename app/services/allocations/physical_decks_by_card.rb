module Allocations
  # Which of a user's physical decks hold given cards, as a Hash of card id =>
  # [{ id:, key:, name: }], in one query whatever the card count. The over-allocation
  # report asks this twice with two different conditions — which decks hold real
  # copies, and which decks still have proxy slots to convert — and both used to
  # be answered one card at a time, an N+1 over the over-allocated cards.
  #
  # SQL cannot return the nested shape, so the rows are grouped in Ruby.
  class PhysicalDecksByCard < ApplicationService
    CONDITIONS = {
      # Decks committing at least one real copy of the card: the source side of a
      # reallocation, and the "where are those copies?" column of the report.
      holding_real_copies: "deck_cards.owned_copies > 0",
      # Decks whose copies of the card are not all real yet: the only valid
      # destinations for a reallocation, since a proxy slot is what receives one.
      with_proxy_slots: "deck_cards.owned_copies < deck_cards.quantity"
    }.freeze

    # `holding` is a CONDITIONS key rather than a SQL fragment, so no caller can
    # reach the WHERE clause with a string of its own.
    def initialize(user:, card_ids:, holding:)
      @user = user
      @card_ids = Array(card_ids)
      @condition = CONDITIONS.fetch(holding)
    end

    def call
      return {} if @card_ids.empty?

      rows = @user.decks.where(physical: true)
                  .joins(:deck_cards)
                  .where(deck_cards: { card_id: @card_ids })
                  .where(@condition)
                  .distinct
                  .pluck("deck_cards.card_id", "decks.id", "decks.key", "decks.name")

      # Both identifiers, on purpose: `key` addresses the deck in a link, `id` is what the
      # reallocation form's from_deck_id/to_deck_id selects carry — those reference a row
      # rather than a page. This hash is also what ListOverAllocationsTool serialises to
      # MCP clients, so the key added here is what makes reallocate_owned_copies callable
      # from the report (see Task 4).
      rows.group_by(&:first).transform_values do |group|
        group.map { |(_card_id, deck_id, deck_key, deck_name)| { id: deck_id, key: deck_key, name: deck_name } }
      end
    end
  end
end
