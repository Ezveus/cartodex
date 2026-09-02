module Decks
  # The public listing of shared decks. Same rows as the owner's index, minus everything that
  # compares a deck against a collection the reader does not have: no support or proxies
  # filter, no over-allocation marker, no actions dropdown, no compare bar, no import panel.
  class SharedIndexView < ApplicationComponent
    FORMAT_OPTIONS = [ [ "All formats", "" ] ].freeze

    def initialize(decks:, filters:, archetype_options:, page:, pages:)
      @decks = decks
      @filters = filters
      @archetype_options = archetype_options
      @page = page
      @pages = pages
    end

    def view_template
      div(class: "decks-container") do
        h1 { "Shared decks" }
        filter_bar
        if @decks.any?
          div(class: "deck-list") do
            @decks.each { |deck| render Decks::DeckCard.new(deck: deck, with_actions: false, public_listing: true) }
          end
          pagination if @pages > 1
        else
          p(class: "empty-state") { "No shared decks yet." }
        end
      end
    end

    private

    def filter_bar
      form(action: shared_decks_path, method: "get", class: "deck-filters", data: { controller: "card-filter" }) do
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

    def pagination
      nav(class: "pagination") do
        link_to "Previous", shared_decks_path(**@filters.compact, page: @page - 1), class: "btn btn-secondary btn-sm" if @page > 1
        span(class: "pagination-position") { "Page #{@page} of #{@pages}" }
        link_to "Next", shared_decks_path(**@filters.compact, page: @page + 1), class: "btn btn-secondary btn-sm" if @page < @pages
      end
    end
  end
end
