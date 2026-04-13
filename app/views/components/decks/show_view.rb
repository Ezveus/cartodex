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
        result_dialog
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
        stat(@deck.deck_cards.sum(&:quantity), "cards", data: { deck_totals_target: "total" })
        stat(counts["win"], "wins")
        stat(counts["loss"], "losses")
        stat(counts["draw"], "draws")
        stat(counts["timeout"], "timeouts")
      end
    end

    def stat(value, label, **data)
      div(class: "stat") do
        span(class: "stat-value", **data) { value.to_s }
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

    def result_dialog
      dialog(class: "result-modal", data: { result_modal_target: "dialog" }) do
        div(class: "result-modal-content") do
          h2 { "Log Result" }
          input(type: "hidden", data: { result_modal_target: "resultInput" })
          input(type: "hidden", data: { result_modal_target: "archetypeId" })

          div(class: "result-type-buttons") do
            %w[win loss draw timeout].each do |r|
              button(
                type: "button",
                class: "result-type-btn result-#{r}",
                data: { result: r, action: "result-modal#selectResult", result_modal_target: "resultBtn" }
              ) { r.capitalize }
            end
          end

          div(class: "form-group") do
            label(class: "form-label") { "Opponent archetype" }
            input(
              type: "text",
              class: "form-input",
              placeholder: "Search archetype...",
              data: { result_modal_target: "archetypeInput", action: "input->result-modal#searchArchetypes" }
            )
            div(class: "archetype-search-results", data: { result_modal_target: "archetypeResults" })
          end

          create_archetype_section

          div(class: "form-group") do
            label(class: "form-label") { "Notes (optional)" }
            textarea(class: "form-input", rows: "2", data: { result_modal_target: "notesInput" })
          end

          div(class: "form-actions result-modal-actions") do
            button(class: "btn btn-primary", data: { action: "result-modal#submit" }) { "Save" }
            button(class: "btn btn-secondary", type: "button", data: { action: "result-modal#close" }) { "Cancel" }
          end
        end
      end
    end
    def create_archetype_section
      div(class: "create-archetype-section", style: "display: none;", data: { result_modal_target: "createSection" }) do
        p(class: "form-label", style: "font-weight: 600; margin-bottom: 0.5rem;") { "New archetype" }

        div(class: "form-group") do
          label(class: "form-label") { "Primary Pokémon" }
          input(type: "hidden", data: { result_modal_target: "primaryId" })
          input(
            type: "text",
            class: "form-input",
            placeholder: "Search Pokémon...",
            data: { result_modal_target: "primaryInput", action: "input->result-modal#searchPrimary" }
          )
          div(class: "archetype-search-results", data: { result_modal_target: "primaryResults" })
        end

        div(class: "form-group") do
          label(class: "form-label") { "Secondary Pokémon (optional)" }
          input(type: "hidden", data: { result_modal_target: "secondaryId" })
          input(
            type: "text",
            class: "form-input",
            placeholder: "Search Pokémon...",
            data: { result_modal_target: "secondaryInput", action: "input->result-modal#searchSecondary" }
          )
          div(class: "archetype-search-results", data: { result_modal_target: "secondaryResults" })
        end

        button(type: "button", class: "btn btn-secondary btn-sm", data: { action: "result-modal#cancelCreate" }) { "Cancel new archetype" }
      end
    end
  end
end
