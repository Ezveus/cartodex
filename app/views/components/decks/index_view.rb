module Decks
  class IndexView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "deck_results".freeze

    SUPPORT_OPTIONS = [ [ "All supports", "" ], [ "Physical", "physical" ], [ "TCG Live", "tcg_live" ] ].freeze
    PROXY_OPTIONS = [ [ "Any proxies", "" ], [ "With proxies", "with" ], [ "Without proxies", "without" ] ].freeze

    def initialize(decks:, pending_deck_imports: [], filters: {}, primary_options: [], secondary_options: [], over_allocated_deck_ids: [], over_allocation_count: 0)
      @decks = decks
      @pending_deck_imports = pending_deck_imports
      @filters = filters || {}
      @primary_options = primary_options || []
      @secondary_options = secondary_options || []
      @over_allocated_deck_ids = over_allocated_deck_ids.to_set
      @over_allocation_count = over_allocation_count
    end

    def view_template
      div(class: "decks-container", data: { controller: "decks deck-compare", deck_compare_compare_url_value: compare_decks_path }) do
        render Allocations::OverAllocationBanner.new(count: @over_allocation_count)
        div(class: "decks-header") do
          h1 { "My Decks" }
          div(class: "decks-header-actions") do
            link_to "New Deck", new_deck_path, class: "btn btn-primary"
            link_to "Import Deck", "#", class: "btn btn-secondary", data: { action: "decks#openImport" }
            link_to "Matchups", matchups_decks_path, class: "btn btn-secondary"
          end
        end

        filter_bar

        render Ui::DeckImport.new(pending_imports: @pending_deck_imports)

        # Everything inside this frame is frame-scoped by default, so each deck link
        # and dropdown action carries data-turbo-frame="_top" (see Decks::DeckCard).
        #
        # compare_bar lives outside the frame but counts the checkboxes inside it, so
        # a filter swap replaces them with unchecked ones while the bar keeps its
        # stale count. turbo:frame-load re-runs the controller's own update path.
        turbo_frame_tag(FRAME_ID, data: { action: "turbo:frame-load->deck-compare#update" }) do
          div(class: "decks-grid", id: "decks-grid") do
            if @decks.any?
              @decks.each { |deck| render Decks::DeckCard.new(deck: deck, over_allocated: @over_allocated_deck_ids.include?(deck.id)) }
            else
              p(id: "decks-empty") do
                plain "No decks match these filters. "
                link_to "Clear filters", decks_path, data: { turbo_frame: "_top" }
                plain "."
              end
            end
          end
        end

        compare_bar
      end
    end

    private

    def compare_bar
      div(class: "deck-compare-bar", data: { deck_compare_target: "bar" }) do
        span(class: "deck-compare-bar-label") do
          span(data: { deck_compare_target: "count" }) { "0" }
          plain " selected (pick 2–4)"
        end
        button(
          type: "button",
          class: "btn btn-primary btn-sm",
          data: { deck_compare_target: "button", action: "deck-compare#compare" }
        ) { "Compare" }
        button(
          type: "button",
          class: "btn btn-secondary btn-sm",
          data: { action: "deck-compare#clear" }
        ) { "Clear" }
      end
    end

    def filter_bar
      form(
        action: decks_path,
        method: "get",
        class: "deck-filters",
        data: { controller: "card-filter", turbo_frame: FRAME_ID, turbo_action: "replace" }
      ) do
        search_input
        filter_select(:format, format_options)
        filter_select(:primary, primary_options) if @primary_options.any?
        filter_select(:secondary, secondary_options) if @secondary_options.any?
        filter_select(:support, SUPPORT_OPTIONS)
        filter_select(:proxies, PROXY_OPTIONS)
        link_to "Clear", decks_path, class: "btn btn-secondary btn-sm" if active_filters?
      end
    end

    def search_input
      input(
        type: "search",
        name: "q",
        value: @filters[:q],
        placeholder: "Deck or archetype name…",
        class: "form-input deck-filter-search",
        autocomplete: "off",
        aria_label: "Search decks",
        data: { action: "input->card-filter#debounce" }
      )
    end

    def filter_select(name, options)
      selected = @filters[name].to_s
      select(name: name, class: "form-input deck-filter-select", data: { action: "change->card-filter#submit" }) do
        options.each do |label, value|
          if value.to_s == selected
            option(value: value, selected: true) { label }
          else
            option(value: value) { label }
          end
        end
      end
    end

    def format_options
      [ [ "All formats", "" ] ] + Deck::FORMAT_LABELS.map { |value, label| [ label, value ] }
    end

    def primary_options
      [ [ "Any primary", "" ] ] + @primary_options.map { |name, id| [ name, id.to_s ] }
    end

    def secondary_options
      [ [ "Any secondary", "" ] ] + @secondary_options.map { |name, id| [ name, id.to_s ] }
    end

    def active_filters?
      @filters.values.any?(&:present?)
    end
  end
end
