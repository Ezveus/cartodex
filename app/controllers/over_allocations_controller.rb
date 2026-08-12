class OverAllocationsController < ApplicationController
  def index
    @over_allocations = Allocations::OverAllocations.call(user: current_user)
    card_ids = @over_allocations.map { |o| o[:card_id] }
    @cards_by_id = Card.where(id: card_ids).index_by(&:id)

    # Per card: physical decks holding it that still have proxy slots to convert
    # into reals (owned_copies < quantity) — the valid reallocation targets. One
    # grouped query for every card, where this ran one per over-allocated card.
    @targets_by_card = Allocations::PhysicalDecksByCard.call(
      user: current_user, card_ids: card_ids, holding: :with_proxy_slots
    )
  end

  def reallocate
    from_deck = current_user.decks.find(params[:from_deck_id])
    to_deck = current_user.decks.find(params[:to_deck_id])
    card = Card.find(params[:card_id])

    Decks::OwnedCopiesReallocator.call(
      from_deck: from_deck, to_deck: to_deck, card: card, quantity: params[:quantity].to_i
    )
    redirect_to over_allocations_path, notice: "Real copies moved."
  rescue ArgumentError, Decks::OwnedCopiesReallocator::NotPhysicalError => e
    redirect_to over_allocations_path, alert: e.message
  rescue ActiveRecord::RecordNotFound
    redirect_to over_allocations_path, alert: "Card not found in one of the decks."
  end
end
