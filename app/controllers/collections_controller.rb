class CollectionsController < ApplicationController
  CARD_TYPES = %w[Pokémon Trainer Energy].freeze

  def index
    @card_sets = CardSet.by_release
    @card_types = CARD_TYPES

    @selected_set_code = params[:set].presence
    @selected_type = params[:type].presence.then { |t| CARD_TYPES.include?(t) ? t : nil }
    @query = params[:q].to_s.strip

    scope = current_user.collections.with_cards.includes(card: :card_set)
    scope = scope.joins(:card).where(cards: { card_type: @selected_type }) if @selected_type
    scope = scope.joins(card: :card_set).where(card_sets: { code: @selected_set_code }) if @selected_set_code
    scope = scope.joins(:card).merge(Card.name_matching(@query)) if @query.present?

    @collections = scope.order("cards.name").to_a
    @total_unique = @collections.size
    @total_copies = @collections.sum(&:quantity)
    @availability = Allocations::Availability.for_cards(user: current_user, cards: @collections.map(&:card))
    @over_allocation_count = Allocations::OverAllocations.call(user: current_user).size
  end
end
