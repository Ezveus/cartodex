module Decks
  # The public listing of shared decks. Same rows as the owner's index, minus everything that
  # compares a deck against a collection the reader does not have: no support or proxies
  # filter, no over-allocation marker, no actions dropdown, no compare bar, no import panel.
  class SharedIndexView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "shared_deck_results".freeze

    FORMAT_OPTIONS = [ [ "All formats", "" ] ].freeze

    def initialize(decks:, filters:, archetype_options: [], page: 1, pages: 1)
      @decks = decks
      @filters = filters || {}
      # nil, not just absent: a Turbo Frame request skips building these — see
      # DecksController#results_frame_request?.
      @archetype_options = archetype_options || []
      @page = page
      @pages = pages
    end

    def view_template
      div(class: "decks-container") do
        h1 { "Shared decks" }
        filter_bar
        # Rows, pager and empty state inside the frame; the filter bar outside it. A keystroke
        # then costs the grid and nothing else — no layout, no archetype options query.
        turbo_frame_tag(FRAME_ID) do
          if @decks.any?
            # decks-grid, not a name of this page's own: application.css is the app's only
            # stylesheet and every class here has to exist in it. The owner's index lays its
            # rows out with this one.
            div(class: "decks-grid") do
              @decks.each { |deck| render Decks::DeckCard.new(deck: deck, with_actions: false, public_listing: true) }
            end
            pagination
          else
            p(class: "empty-state") { "No shared decks yet." }
          end
        end
      end
    end

    private

    def filter_bar
      form(
        action: shared_decks_path, method: "get", class: "deck-filters",
        data: { controller: "card-filter", turbo_frame: FRAME_ID, turbo_action: "replace" }
      ) do
        input(
          type: "search", name: "q", value: @filters[:q], placeholder: "Search shared decks…",
          class: "form-input deck-filter-search", autocomplete: "off", aria_label: "Search shared decks",
          data: { action: "input->card-filter#debounce" }
        )
        filter_select(:format, FORMAT_OPTIONS + Deck::FORMAT_LABELS.map { |value, label| [ label, value ] })
        filter_select(:primary, [ [ "Any archetype card", "" ] ] + @archetype_options) if @archetype_options.any?
      end
    end

    def filter_select(name, options)
      render Ui::FilterSelect.new(name: name, options: options, selected: @filters[name])
    end

    # Borrows the card index's pager classes rather than inventing decks-only ones: they are
    # the app's only styled pager, and this page has no reason to look different from it.
    #
    # These links sit *inside* FRAME_ID, so Turbo navigates the frame rather than the page —
    # which is what a pager wants, but it leaves the address bar behind. turbo_action "replace"
    # is what puts ?page= back into it, so a reload or a copied link still lands on the page the
    # reader was looking at. (The deck rows escape the frame the other way, through
    # Decks::DeckCard's own data-turbo-frame="_top".)
    def pagination
      render Ui::Pagination.new(
        page: @page, pages: @pages, turbo_action: "replace",
        href: ->(page) { shared_decks_path(**@filters.compact, page: page) }
      )
    end
  end
end
