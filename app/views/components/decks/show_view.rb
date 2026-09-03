module Decks
  class ShowView < ApplicationComponent
    def initialize(deck:, editing: false, tournament_profiles: [], availability: {}, over_allocated_card_ids: [],
                   swappable_card_ids: [])
      @deck = deck
      @editing = editing
      @tournament_profiles = tournament_profiles
      @availability = availability
      @over_allocated_card_ids = over_allocated_card_ids.to_set
      @swappable_card_ids = swappable_card_ids.to_set
    end

    def view_template
      div(class: "deck-show-container", data: {
        controller: "card-preview deck-totals result-modal tournament-pdf deck-proxies share-modal",
        action: "deck-card-quantity:changed->deck-totals#updateTotals " \
                "deck-proxies:changed->deck-proxies#toggle",
        result_modal_deck_key_value: @deck.key
      }) do
        header_section
        stats_section
        div(class: "deck-show-content") do
          main_section
          preview_section
        end
        render Decks::ResultModal.new(deck: @deck)
        render Decks::ShareModal.new(deck: @deck)
        render Decks::TournamentPdfModal.new(deck: @deck, tournament_profiles: @tournament_profiles)
      end
    end

    private

    TRAINER_SUBTYPE_LABELS = {
      "Supporter" => "Supporter",
      "Item" => "Item",
      "Pokémon Tool" => "Tool",
      "Stadium" => "Stadium"
    }.freeze

    def header_section
      div(class: "deck-show-header") do
        render Decks::HeaderFrame.new(deck: @deck, editing: @editing)
        link_to "Back to Decks", decks_path, class: "btn btn-secondary"
      end
      nav(class: "deck-actions-bar") do
        button(class: "btn btn-primary btn-sm", data: { action: "result-modal#open" }) { "Log Result" }
        render Decks::ExportDropdown.new(deck: @deck, tournament_pdf: true)
        link_to "Results", deck_deck_results_path(@deck), class: "btn btn-secondary btn-sm"
        link_to "Stats", stats_deck_path(@deck), class: "btn btn-secondary btn-sm"
        render Decks::ActionsDropdown.new(deck: @deck, edit_frame: Decks::HeaderFrame::FRAME_ID, share: true)
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

        if (group = card_groups["Pokémon"]).present?
          card_type_section("Pokémon", group)
        end
        if (group = card_groups["Trainer"]).present?
          trainer_section(group)
        end
        if (group = card_groups["Energy"]).present?
          card_type_section("Energy", group)
        end
      end
    end

    def card_search
      render Ui::SearchInput.new(
        placeholder: "Search cards to add...",
        input_class: "form-input card-search-input",
        wrapper_class: "deck-card-search",
        controller: "card-search",
        card_search_deck_key_value: @deck.key,
        input_target: :card_search_target,
        input_action: "input->card-search#search",
        results_target: :card_search_target
      )
    end

    def card_type_section(type, group)
      div(class: "deck-section") do
        section_heading(:h2, type, group)
        card_list(group)
      end
    end

    def trainer_section(group)
      div(class: "deck-section-group") do
        h2 { "Trainer" }
        subtype_groups = group.group_by { |dc| dc.card.subtype }

        TRAINER_SUBTYPE_LABELS.each do |subtype, label|
          subgroup = subtype_groups.delete(subtype)
          trainer_subtype_section(label, subgroup) if subgroup.present?
        end

        other_group = subtype_groups.values.flatten
        trainer_subtype_section("Other", other_group) if other_group.present?
      end
    end

    def trainer_subtype_section(label, group)
      div(class: "deck-section deck-subsection") do
        section_heading(:h3, label, group)
        card_list(group)
      end
    end

    def section_heading(tag, label, group)
      send(tag) do
        plain "#{label} ("
        span(data: { deck_totals_target: "sectionTotal" }) { group.sum(&:quantity).to_s }
        plain " — "
        span(data: { deck_totals_target: "sectionUnique" }) { group.size.to_s }
        plain " unique)"
      end
    end

    def card_list(group)
      ul(class: "deck-card-list") do
        group.sort_by { |dc| dc.card.name }.each do |dc|
          availability = @availability[dc.card_id]
          max_owned = availability ? [ dc.quantity, availability.available ].min : 0
          render Decks::DeckCardItem.new(
            deck_card: dc,
            deck_key: @deck.key,
            physical: @deck.physical?,
            max_owned: max_owned,
            over_allocated: @over_allocated_card_ids.include?(dc.card_id),
            swappable: @swappable_card_ids.include?(dc.card_id)
          )
        end
      end
    end

    def preview_section
      render Ui::CardPreview.new(wrapper_class: "deck-show-preview")
      render Ui::CardPreviewModal.new
    end
  end
end
