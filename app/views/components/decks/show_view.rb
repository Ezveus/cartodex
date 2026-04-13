module Decks
  class ShowView < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      div(class: "deck-show-container", data: {
        controller: "card-preview deck-totals result-modal",
        action: "deck-card-quantity:changed->deck-totals#updateTotals",
        result_modal_deck_id_value: @deck.id
      }) do
        header_section
        stats_section
        div(class: "deck-show-content") do
          main_section
          preview_section
        end
        render Decks::ResultModal.new
      end
    end

    private

    def header_section
      div(class: "deck-show-header") do
        div do
          h1 { @deck.name }
          p(class: "deck-show-description") { @deck.description } if @deck.description.present?
        end
        link_to "Back to Decks", helpers.decks_path, class: "btn btn-secondary"
      end
      nav(class: "deck-actions-bar") do
        button(class: "btn btn-primary btn-sm", data: { action: "result-modal#open" }) { "Log Result" }
        button(
          class: "btn btn-secondary btn-sm",
          data: { controller: "clipboard", clipboard_url_value: helpers.export_deck_path(@deck), action: "clipboard#copy" }
        ) { "Export" }
        link_to "Results", helpers.deck_deck_results_path(@deck), class: "btn btn-secondary btn-sm"
        link_to "Stats", helpers.stats_deck_path(@deck), class: "btn btn-secondary btn-sm"
      end
    end

    def stats_section
      counts = @deck.result_counts

      div(class: "deck-show-stats") do
        render Ui::Stat.new(value: @deck.deck_cards.sum(&:quantity), label: "cards", value_data: { deck_totals_target: "total" })
        render Ui::Stat.new(value: counts["win"], label: "wins")
        render Ui::Stat.new(value: counts["loss"], label: "losses")
        render Ui::Stat.new(value: counts["draw"], label: "draws")
        render Ui::Stat.new(value: counts["timeout"], label: "timeouts")
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
      render Ui::SearchInput.new(
        placeholder: "Search cards to add...",
        input_class: "form-input card-search-input",
        wrapper_class: "deck-card-search",
        controller: "card-search",
        card_search_deck_id_value: @deck.id,
        input_target: :card_search_target,
        input_action: "input->card-search#search",
        results_target: :card_search_target
      )
    end

    def card_type_section(type, group)
      div(class: "deck-section") do
        h2 { "#{type} (#{group.sum(&:quantity)})" }
        ul(class: "deck-card-list") do
          group.sort_by { |dc| dc.card.name }.each do |dc|
            render Decks::DeckCardItem.new(deck_card: dc, deck_id: @deck.id)
          end
        end
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
