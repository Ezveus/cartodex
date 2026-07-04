module Decks
  class DeckCard < ApplicationComponent
    def initialize(deck:, with_actions: true, over_allocated: false)
      @deck = deck
      @with_actions = with_actions
      @over_allocated = over_allocated
    end

    def view_template
      hot = @deck.hot?
      item_class = hot ? "deck-item is-foil" : "deck-item"

      div(class: item_class, id: "deck-#{@deck.id}") do
        type_stripe
        if hot
          div(class: "deck-foil-sheen", aria_hidden: "true")
          span(class: "deck-hot-flag") { "★ #{(@deck.win_rate * 100).round}%" }
        end
        input(
          type: "checkbox",
          class: "deck-compare-checkbox",
          value: @deck.id,
          aria_label: "Select #{@deck.name} to compare",
          data: { deck_compare_target: "checkbox", action: "deck-compare#toggle" }
        )
        a(href: Rails.application.routes.url_helpers.deck_path(@deck), class: "deck-item-link") do
          h2 { @deck.name }
          render Decks::ClassificationBadges.new(deck: @deck, over_allocated: @over_allocated)
          p(class: "deck-description") { @deck.description } if @deck.description.present?
          p(class: "deck-card-count") { "#{@deck.deck_cards.sum(&:quantity)} cards" }
        end
        if @with_actions
          div(class: "deck-item-actions") do
            render Decks::ActionsDropdown.new(deck: @deck)
          end
        end
      end
    end

    private

    # A thin bar at the top edge of the card, coloured by the deck's energy
    # type(s). Two types blend into a gradient; one fills solid.
    def type_stripe
      colors = @deck.energy_types.filter_map { |t| Card::TYPE_TOKENS[t] }.map { |token| "var(--#{token})" }
      return if colors.empty?

      background = colors.one? ? colors.first : "linear-gradient(90deg, #{colors.first}, #{colors.last})"
      div(class: "deck-stripe", style: "background: #{background}")
    end
  end
end
