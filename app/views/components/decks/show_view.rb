module Decks
  class ShowView < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      div(class: "deck-show-container", data: { controller: "card-preview" }) do
        header_section
        stats_section
        div(class: "deck-show-content") do
          main_section
          preview_section
        end
      end
    end

    private

    def header_section
      div(class: "deck-show-header") do
        div do
          h1 { @deck.name }
          p(class: "deck-show-description") { @deck.description } if @deck.description.present?
        end
        div(class: "decks-header-actions") do
          button(
            class: "btn btn-primary",
            data: { controller: "clipboard", clipboard_url_value: helpers.export_deck_path(@deck), action: "clipboard#copy" }
          ) { "Export" }
          link_to "Back to Decks", helpers.decks_path, class: "btn btn-secondary"
        end
      end
    end

    def stats_section
      wins = @deck.deck_results.count { |r| r.result == "win" }
      losses = @deck.deck_results.count { |r| r.result == "loss" }

      div(class: "deck-show-stats") do
        stat(@deck.deck_cards.sum(&:quantity), "cards")
        stat(wins, "wins")
        stat(losses, "losses")
      end
    end

    def stat(value, label)
      div(class: "stat") do
        span(class: "stat-value") { value.to_s }
        span(class: "stat-label") { label }
      end
    end

    def main_section
      div(class: "deck-show-main") do
        card_search
        card_groups = @deck.deck_cards.group_by { |dc| dc.card.card_type }
        %w[Pokémon Trainer Energy].each do |type|
          group = card_groups[type]
          next unless group.present?
          card_type_section(type, group)
        end
      end
    end

    def card_search
      div(class: "deck-card-search", data: { controller: "card-search", card_search_deck_id_value: @deck.id }) do
        input(
          type: "text",
          placeholder: "Search cards to add...",
          data: { card_search_target: "input", action: "input->card-search#search" },
          class: "form-input card-search-input"
        )
        div(data: { card_search_target: "results" }, class: "card-search-results")
      end
    end

    def card_type_section(type, group)
      div(class: "deck-section") do
        h2 { "#{type} (#{group.sum(&:quantity)})" }
        ul(class: "deck-card-list") do
          group.sort_by { |dc| dc.card.name }.each { |dc| deck_card_item(dc) }
        end
      end
    end

    def deck_card_item(dc)
      li(
        class: "deck-card-item",
        data: {
          card_preview_url: dc.card.image_url,
          card_preview_card_id: dc.card.id,
          action: "mouseenter->card-preview#show",
          controller: "deck-card-quantity",
          deck_card_quantity_deck_id_value: @deck.id,
          deck_card_quantity_card_id_value: dc.card.id,
          deck_card_quantity_quantity_value: dc.quantity
        }
      ) do
        div(class: "deck-card-qty-controls") do
          button(class: "qty-btn", data: { action: "deck-card-quantity#decrement" }) { "-" }
          span(class: "deck-card-qty") { dc.quantity.to_s }
          button(class: "qty-btn", data: { action: "deck-card-quantity#increment" }) { "+" }
        end
        span(class: "deck-card-name") { dc.card.name }
        span(class: "deck-card-set") { "#{dc.card.set_name} #{dc.card.set_number}" }
      end
    end

    def preview_section
      div(class: "deck-show-preview") do
        image_tag "", data: { card_preview_target: "image" }, class: "card-preview-image", style: "display: none"
        link_to "View card details", "#", data: { card_preview_target: "link" }, class: "card-preview-link", style: "display: none"
      end
    end
  end
end
