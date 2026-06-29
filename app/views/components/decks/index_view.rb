module Decks
  class IndexView < ApplicationComponent
    SUPPORT_OPTIONS = [ [ "All supports", "" ], [ "Physical", "physical" ], [ "TCG Live", "tcg_live" ] ].freeze
    PROXY_OPTIONS = [ [ "Any proxies", "" ], [ "With proxies", "with" ], [ "Without proxies", "without" ] ].freeze

    def initialize(decks:, pending_deck_imports: [], filters: {}, archetype_options: [])
      @decks = decks
      @pending_deck_imports = pending_deck_imports
      @filters = filters || {}
      @archetype_options = archetype_options || []
    end

    def view_template
      div(class: "decks-container", data: { controller: "decks" }) do
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

        div(class: "decks-grid", id: "decks-grid") do
          if @decks.any?
            @decks.each { |deck| render Decks::DeckCard.new(deck: deck) }
          else
            p(id: "decks-empty") do
              plain "No decks match these filters. "
              link_to "Clear filters", decks_path
              plain "."
            end
          end
        end
      end
    end

    private

    def filter_bar
      form(action: decks_path, method: "get", class: "deck-filters", data: { controller: "card-filter" }) do
        filter_select(:format, format_options)
        filter_select(:archetype, archetype_options) if @archetype_options.any?
        filter_select(:support, SUPPORT_OPTIONS)
        filter_select(:proxies, PROXY_OPTIONS)
        link_to "Clear", decks_path, class: "btn btn-secondary btn-sm" if active_filters?
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

    def format_options
      [ [ "All formats", "" ] ] + Deck::FORMAT_LABELS.map { |value, label| [ label, value ] }
    end

    def archetype_options
      [ [ "All archetypes", "" ] ] + @archetype_options.map { |name, id| [ name, id.to_s ] }
    end

    def active_filters?
      @filters.values.any?(&:present?)
    end
  end
end
