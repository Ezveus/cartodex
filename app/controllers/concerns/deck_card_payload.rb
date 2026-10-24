# The deck lookup and the JSON shape shared by every endpoint that writes a deck's cards: the row
# itself, and what the deck page needs to redraw the card in place.
module DeckCardPayload
  extend ActiveSupport::Concern

  private

  def set_deck
    @deck = current_user.decks.find_by!(key: params[:deck_id])
  end

  # The refusals a write service raises, answered as 422 — a quantity that is not an integer, a
  # real count the collection cannot back, a ⇄ between cards that are not one, a deck that is not
  # physical. Scoped to the write and not to the action, so that an ArgumentError raised while
  # rendering the answer is a bug that surfaces rather than a refusal the member is shown.
  def refusing
    yield
  rescue ArgumentError, Decks::OwnedCopiesSetter::NotPhysicalError => e
    render json: { errors: [ e.message ] }, status: :unprocessable_entity
    nil
  end

  # Everything deck_rows_controller.js needs after a write to `card`, so that it computes nothing:
  # the card's whole state (every printing, with the numbers its controls show and are bounded
  # by), its rows rendered by the components the page renders them with, where each goes, every
  # section's counts, and the deck's total and Proxies flag. The shape is the frozen contract in
  # docs/superpowers/plans/2026-10-24-deck-fingerprint-rows.md ("API").
  #
  # Read from a fresh load of the deck: the write went through a service that may have loaded the
  # association before it changed. `card_set` is what the set view's sections are keyed on.
  def fingerprint_payload(card)
    group = params[:group] == "set" ? :set : :type
    deck = current_user.decks.includes(deck_cards: { card: :card_set }).find(@deck.id)
    states = Decks::FingerprintStates.call(user: current_user, deck: deck)
    sections = Decks::Layout.call(states: states, group: group)
    key = card.fingerprint_key

    placed = sections.select { |section| section.rows.any? { |row| row.state.key == key } }
    shells = placed.map(&:key) | placed.filter_map(&:parent_key)

    {
      fingerprint_key: key,
      fingerprint: states[key]&.as_json,
      rows: placed.flat_map { |section| rows_json(section, key, deck, group) },
      sections: sections.map { |section| section_json(section, shells.include?(section.key)) },
      deck: { has_proxies: deck.has_proxies?, total: deck.deck_cards.sum(&:quantity) }
    }
  end

  def rows_json(section, key, deck, group)
    section.rows.select { |row| row.state.key == key }.map do |row|
      html = render_to_string(Decks::OwnerRow.for(row, deck: deck, group: group), layout: false)
      { key: row.key, section: section.key, html: html }
    end
  end

  # `rows` and the empty shell only where the answer may need to create the section: those it
  # places a row in, and their parent.
  def section_json(section, shell)
    json = { key: section.key, parent: section.parent_key, total: section.total, unique: section.unique }
    json[:noun] = section.noun if section.kind == :set
    return json unless shell

    json.merge(
      rows: section.rows.map(&:key),
      html: render_to_string(Decks::DeckSection.new(section: section), layout: false)
    )
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
