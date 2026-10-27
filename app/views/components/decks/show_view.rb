module Decks
  class ShowView < ApplicationComponent
    # The two ways the list is grouped, in the order the control offers them: the page's own default
    # first. Carried by `?group=set`, never stored — see DecksController#deck_grouping.
    GROUPINGS = [ [ :type, "Type" ], [ :set, "Set" ] ].freeze

    # How the list is drawn: rows, or Decks::ImageGrid's read-only tiles. Carried by `?view=images`
    # — see DecksController#deck_view. Both pages offer it.
    VIEWS = [ [ :list, "List" ], [ :images, "Images" ] ].freeze

    # `states` is Decks::FingerprintStates.call for this deck and reader: every number a row shows
    # or is bounded by, computed once by the controller.
    def initialize(deck:, states:, editing: false, tournament_profiles: [], group: :type, view: :list)
      @deck = deck
      @states = states
      @group = group
      @view = view
      @editing = editing
      @tournament_profiles = tournament_profiles
    end

    def view_template
      div(class: "deck-show-container", data: {
        controller: "card-preview deck-rows disclosure result-modal tournament-pdf deck-proxies share-modal",
        action: "card-search:add->deck-rows#add deck-proxies:changed->deck-proxies#toggle",
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

    # Held by Decks::Layout, which places every row of the page; why both Tool spellings share a
    # label is written there.
    TRAINER_SUBTYPE_LABELS = Decks::Layout::TRAINER_SUBTYPE_LABELS

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
        render Ui::Stat.new(value: @deck.deck_cards.sum(&:quantity), label: "cards", value_data: { deck_rows_target: "total" })
        render Ui::Stat.new(value: counts["win"], label: "wins")
        render Ui::Stat.new(value: counts["loss"], label: "losses")
        render Ui::Stat.new(value: counts["draw"], label: "draws")
        render Ui::Stat.new(value: counts["timeout"], label: "timeouts")
      end
    end

    def set_view? = @group == :set

    # Nil in the type view, which URL helpers and Phlex attributes both drop.
    def group_param = (set_view? ? "set" : nil)

    # `data-deck-group` says which view the list is in; the rows' own URLs carry it to the API.
    def images_view? = @view == :images

    # The image view is read-only: no card search, and no `sections` target, so deck_rows_controller.js
    # has no list to place a row into. Its states are FingerprintStates.deck_only (the controller's
    # choice), which the owner's rows could not be drawn from.
    def main_section
      div(class: [ "deck-show-main", ("deck-show-main--images" if images_view?) ].compact.join(" "),
          data: { deck_group: group_param }) do
        card_search unless images_view?
        div(class: "deck-mode-bar") do
          group_links
          view_links
        end
        sections = Decks::Layout.call(states: @states, group: @group)
        if images_view?
          render Decks::ImageGrid.new(sections: sections)
        else
          render Decks::DeckSections.new(
            sections: sections,
            row: ->(row) { Decks::OwnerRow.for(row, deck: @deck, group: @group) },
            data: { deck_rows_target: "sections" }
          )
        end
      end
    end

    # Always the show page, even from a full-page edit; each control keeps the other's parameter.
    def group_links
      render Decks::ModeLinks.new(label: "Group by", current: @group, modes: GROUPINGS.map { |mode, label|
        [ mode, label, deck_path(@deck, group: (mode == :set ? "set" : nil), view: view_param) ]
      })
    end

    def view_links
      render Decks::ModeLinks.new(label: "View", current: @view, modes: VIEWS.map { |mode, label|
        [ mode, label, deck_path(@deck, group: group_param, view: (mode == :images ? "images" : nil)) ]
      })
    end

    def view_param = (images_view? ? "images" : nil)

    # The search posts to the cards endpoint with the page's view on it, so its answer carries rows
    # in that view and deck_rows_controller.js places them without a reload.
    def card_search
      render Ui::SearchInput.new(
        placeholder: "Search cards to add...",
        input_class: "form-input card-search-input",
        wrapper_class: "deck-card-search",
        controller: "card-search",
        card_search_url_value: api_deck_cards_path(@deck, group: group_param),
        input_target: :card_search_target,
        input_action: "input->card-search#search",
        results_target: :card_search_target
      )
    end

    def preview_section
      render Ui::CardPreview.new(wrapper_class: "deck-show-preview")
      render Ui::CardPreviewModal.new
    end
  end
end
