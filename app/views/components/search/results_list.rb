module Search
  # Three groups of options, a "no matches" line, or — when the query was too short to search —
  # nothing at all.
  class ResultsList < ApplicationComponent
    def initialize(results:)
      @results = results
    end

    def view_template
      if @results.blank?
        # Nothing: the query is too short to have searched.
      elsif @results.any?
        div(class: "spotlight-listbox", role: "listbox", aria_label: "Search results") do
          deck_group
          shared_deck_group
          card_group
          tournament_group
        end
      else
        p(class: "spotlight-empty") { "No matches." }
      end
    end

    private

    def query
      @results.query
    end

    def deck_group
      render ResultGroup.new(
        key: "decks", label: "DECKS", records: @results.decks, total: @results.deck_total,
        index_path: decks_path(q: query), see_all_label: see_all_label(@results.deck_total, "deck")
      ) do |deck|
        option_row(
          dom_id: "spotlight-option-deck-#{deck.id}",
          path: deck_path(deck),
          name: deck.name,
          meta: [ deck.format_label, deck.archetype&.name ].compact.join(" · ")
        )
      end
    end

    def shared_deck_group
      render ResultGroup.new(
        key: "shared_decks", label: "SHARED DECKS", records: @results.shared_decks,
        total: @results.shared_deck_total, index_path: shared_decks_path(q: query),
        see_all_label: see_all_label(@results.shared_deck_total, "shared deck")
      ) do |deck|
        option_row(
          # A distinct prefix, so this group cannot collide with the one above even if the
          # exclusion in Search::Global is ever relaxed. Cheaper than relying on it.
          dom_id: "spotlight-option-shared-deck-#{deck.id}",
          path: deck_path(deck),
          name: deck.name,
          meta: [ deck.format_label, deck.archetype&.name ].compact.join(" · ")
        )
      end
    end

    def card_group
      render ResultGroup.new(
        key: "cards", label: "CARDS", records: @results.cards, total: @results.card_total,
        index_path: cards_path(q: query), see_all_label: see_all_label(@results.card_total, "card")
      ) do |card|
        option_row(
          dom_id: "spotlight-option-card-#{card.id}",
          path: card_path(card),
          name: card.name,
          meta: "#{card.set_name} ##{card.set_number}"
        )
      end
    end

    def tournament_group
      render ResultGroup.new(
        key: "tournaments", label: "TOURNAMENTS", records: @results.tournaments,
        total: @results.tournament_total, index_path: tournaments_path(q: query),
        see_all_label: see_all_label(@results.tournament_total, "tournament")
      ) do |tournament|
        option_row(
          dom_id: "spotlight-option-tournament-#{tournament.id}",
          path: tournament_path(tournament),
          name: tournament.name,
          meta: "#{localize(tournament.date, format: :long)} · #{tournament.tier_label}"
        )
      end
    end

    # "See all 1 deck" / "See all 3 decks" — pluralize keeps the count grammatical at N=1.
    def see_all_label(count, noun)
      "See all #{count} #{noun.pluralize(count)}"
    end

    # data-turbo-frame="_top" so picking a result navigates the whole page instead of replacing
    # the panel with the target page's markup.
    #
    # aria-selected starts out false on every row and the Stimulus controller moves the "true" as
    # the arrow keys walk the list: aria-activedescendant alone points at a row without ever
    # saying it is the selected one.
    def option_row(dom_id:, path:, name:, meta:)
      a(id: dom_id, href: path, role: "option", aria_selected: "false", class: "spotlight-option", data: { turbo_frame: "_top" }) do
        span(class: "spotlight-option-name") { name }
        span(class: "spotlight-option-meta") { meta }
      end
    end
  end
end
