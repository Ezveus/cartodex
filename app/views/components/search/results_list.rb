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
        index_path: decks_path(q: query), see_all_label: "See all #{@results.deck_total} decks"
      ) do |deck|
        option_row(
          dom_id: "spotlight-option-deck-#{deck.id}",
          path: deck_path(deck),
          name: deck.name,
          meta: [ deck.format_label, deck.archetype&.name ].compact.join(" · ")
        )
      end
    end

    def card_group
      render ResultGroup.new(
        key: "cards", label: "CARDS", records: @results.cards, total: @results.card_total,
        index_path: cards_path(q: query), see_all_label: "See all #{@results.card_total} cards"
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
        see_all_label: "See all #{@results.tournament_total} tournaments"
      ) do |tournament|
        option_row(
          dom_id: "spotlight-option-tournament-#{tournament.id}",
          path: tournament_path(tournament),
          name: tournament.name,
          meta: "#{tournament.date} · #{tournament.tier_label}"
        )
      end
    end

    # data-turbo-frame="_top" so picking a result navigates the whole page instead of replacing
    # the panel with the target page's markup.
    def option_row(dom_id:, path:, name:, meta:)
      a(id: dom_id, href: path, role: "option", class: "spotlight-option", data: { turbo_frame: "_top" }) do
        span(class: "spotlight-option-name") { name }
        span(class: "spotlight-option-meta") { meta }
      end
    end
  end
end
