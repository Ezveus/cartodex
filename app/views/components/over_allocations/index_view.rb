module OverAllocations
  class IndexView < ApplicationComponent
    def initialize(over_allocations:, cards_by_id:)
      @over_allocations = over_allocations
      @cards_by_id = cards_by_id
    end

    def view_template
      div(class: "over-allocations-container") do
        h1 { "Over-allocated cards" }

        if @over_allocations.empty?
          p(class: "over-allocations-empty") { "No over-allocations. Everything is balanced." }
        else
          div(class: "over-allocation-list") do
            @over_allocations.each { |over| row(over) }
          end
        end
      end
    end

    private

    def row(over)
      card = @cards_by_id[over[:card_id]]
      div(class: "over-allocation-row") do
        span(class: "over-allocation-card") { card&.name.to_s }
        span(class: "over-allocation-counts") { "owned #{over[:owned]} · committed #{over[:committed]}" }
        div(class: "over-allocation-decks") do
          over[:decks].each do |d|
            link_to d[:name], deck_path(d[:id]), class: "over-allocation-deck-link"
          end
        end
      end
    end
  end
end
