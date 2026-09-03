module OverAllocations
  class IndexView < ApplicationComponent
    def initialize(over_allocations:, cards_by_id:, targets_by_card: {})
      @over_allocations = over_allocations
      @cards_by_id = cards_by_id
      @targets_by_card = targets_by_card
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
            link_to d[:name], deck_path(d[:key]), class: "over-allocation-deck-link"
          end
        end
        reallocation_form(over)
      end
    end

    def reallocation_form(over)
      sources = over[:decks]
      targets = @targets_by_card[over[:card_id]] || []
      return if sources.empty? || targets.empty?

      form_with url: reallocate_over_allocations_path, method: :post, class: "over-allocation-reallocate" do
        input(type: "hidden", name: "card_id", value: over[:card_id])
        select(name: "from_deck_id") { sources.each { |d| option(value: d[:id]) { d[:name] } } }
        select(name: "to_deck_id") { targets.each { |d| option(value: d[:id]) { d[:name] } } }
        input(type: "number", name: "quantity", value: "1", min: "1")
        button(type: "submit") { "Reallocate" }
      end
    end
  end
end
