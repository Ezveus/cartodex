# The deck lookup and the JSON shape shared by every endpoint that writes a deck's cards:
# the row itself, and the deck-wide state a single-card write can flip.
module DeckCardPayload
  extend ActiveSupport::Concern

  private

  def set_deck
    @deck = current_user.decks.find_by!(key: params[:deck_id])
  end

  # A single-card write can flip deck-wide state, so every write answers with it — the deck page
  # edits cards in place and would otherwise keep showing a stale "Proxies" badge. Deliberately
  # not folded into #deck_card_json, which #index calls once per row.
  def with_deck_state(payload)
    payload.merge(deck: deck_state)
  end

  # `has_proxies?` is derived from the deck's cards, so the association has to be dropped first:
  # the write went through a service that may well have loaded it beforehand.
  def deck_state
    @deck.deck_cards.reset
    { has_proxies: @deck.has_proxies? }
  end

  def deck_card_json(deck_card)
    {
      id: deck_card.id,
      quantity: deck_card.quantity,
      owned_copies: deck_card.owned_copies,
      proxies: deck_card.proxies,
      card: {
        id: deck_card.card.id,
        name: deck_card.card.name,
        card_type: deck_card.card.card_type,
        set_name: deck_card.card.set_name,
        set_number: deck_card.card.set_number,
        rarity: deck_card.card.rarity,
        hp: deck_card.card.hp,
        type_symbol: deck_card.card.type_symbol
      }
    }
  end
end
