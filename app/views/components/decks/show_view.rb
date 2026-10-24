module Decks
  class ShowView < ApplicationComponent
    # The two ways the list is grouped, in the order the control offers them: the page's own default
    # first. Carried by `?group=set`, never stored — see DecksController#deck_grouping.
    GROUPINGS = [ [ :type, "Type" ], [ :set, "Set" ] ].freeze

    def initialize(deck:, editing: false, tournament_profiles: [], availability: {}, over_allocated_card_ids: [],
                   swappable_card_ids: [], group: :type)
      @deck = deck
      @group = group
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

    # `cards.subtype` is a free scraped string: Cards::Fetcher#parse_subtype keeps whatever
    # follows "Trainer - " on the page, and that has been "Tool" for every one of the 76 tools in
    # the catalogue while this table only knew "Pokémon Tool" — so every Tool fell through to the
    # "Other" heading below. Both spellings map to one label, and the grouping is done on the
    # label rather than on the raw subtype so a deck holding both spellings gets one section
    # rather than two identically titled ones.
    TRAINER_SUBTYPE_LABELS = {
      "Supporter" => "Supporter",
      "Item" => "Item",
      "Tool" => "Tool",
      "Pokémon Tool" => "Tool",
      "Stadium" => "Stadium"
    }.freeze

    def header_section
      div(class: "deck-show-header") do
        render Decks::HeaderFrame.new(deck: @deck, editing: @editing, group: @group)
        link_to "Back to Decks", decks_path, class: "btn btn-secondary"
      end
      nav(class: "deck-actions-bar") do
        button(class: "btn btn-primary btn-sm", data: { action: "result-modal#open" }) { "Log Result" }
        render Decks::ExportDropdown.new(deck: @deck, owner: true)
        link_to "Results", deck_deck_results_path(@deck), class: "btn btn-secondary btn-sm"
        # "Match stats", not "Stats": the Odds link beside it is also a page of statistics, and one
        # of them is about games played while the other is about the list itself.
        link_to "Match stats", stats_deck_path(@deck), class: "btn btn-secondary btn-sm"
        link_to "Odds", odds_deck_path(@deck), class: "btn btn-secondary btn-sm"
        render Decks::ActionsDropdown.new(deck: @deck, edit_frame: Decks::HeaderFrame::FRAME_ID, share: true,
                                          group: group_param)
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

    def set_view? = @group == :set

    # Nil in the type view, which URL helpers and Phlex attributes both drop.
    def group_param = (set_view? ? "set" : nil)

    # `data-deck-group` is what printing_picker_controller.js reads to reload after a swap: in the
    # set view the swapped card belongs to another section.
    def main_section
      div(class: "deck-show-main", data: { deck_group: group_param }) do
        card_search
        group_links
        set_view? ? set_sections : type_sections
      end
    end

    # The shape and rule of Archetypes::CardReport's mode links: the current view stays a link — a
    # tab that cannot be clicked reads as disabled — told apart by aria-current and a modifier.
    # Always the show page, even from a full-page edit.
    def group_links
      div(class: "deck-group-modes") do
        span(class: "deck-group-modes-label") { "Group by" }
        GROUPINGS.each do |mode, label|
          current = mode == @group
          a(href: deck_path(@deck, group: (mode == :set ? "set" : nil)),
            class: [ "deck-group-mode", ("deck-group-mode--current" if current) ].compact.join(" "),
            aria_current: ("page" if current)) { label }
        end
      end
    end

    def type_sections
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

    # Ordered by Decks::SetGroups, cards included, so card_list is handed `sort: false`.
    def set_sections
      Decks::SetGroups.call(@deck.deck_cards).each do |section|
        div(class: "deck-section deck-set-section", data: { set_code: section.code }) do
          h2 do
            plain "#{section.label} · "
            span(data: { deck_totals_target: "sectionTotal" }) { section.copies.to_s }
            plain " "
            span(data: { deck_totals_target: "sectionNoun" }) { section.copies == 1 ? "card" : "cards" }
          end
          card_list(section.deck_cards, sort: false)
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
        subtype_groups = group.group_by { |dc| TRAINER_SUBTYPE_LABELS.fetch(dc.card.subtype.to_s, "Other") }

        # `uniq` keeps the table's own order — Supporter, Item, Tool, Stadium — while collapsing
        # the two keys that share the Tool label.
        TRAINER_SUBTYPE_LABELS.values.uniq.each do |label|
          subgroup = subtype_groups.delete(label)
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

    def card_list(group, sort: true)
      rows = sort ? group.sort_by { |dc| dc.card.name } : group
      ul(class: "deck-card-list") do
        rows.each do |dc|
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
