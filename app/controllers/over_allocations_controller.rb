class OverAllocationsController < ApplicationController
  def index
    @over_allocations = Allocations::OverAllocations.call(user: current_user)
    @cards_by_id = Card.where(id: @over_allocations.map { |o| o[:card_id] }).index_by(&:id)
  end
end
