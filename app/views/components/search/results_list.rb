module Search
  # Five groups of options, a "no matches" line, or — when the query was too short to search —
  # nothing at all.
  class ResultsList < ApplicationComponent
    # id_prefix keeps the ids unique when the list is on a page that also carries the overlay's
    # own panel: Search::PageView renders this list beside it, and once the overlay has searched,
    # every row would otherwise exist twice — with the page's groups labelled by the overlay's
    # headers.
    #
    # interactive: false drops the listbox semantics. They are only valid with the spotlight's
    # combobox driving them (dashboard-search: aria-activedescendant, the arrow keys); on a page
    # nothing does, and role="option" would hide the rows from a screen reader's links list while
    # the arrow keys did nothing. Same rows, same order, plain links.
    def initialize(results:, id_prefix: "spotlight", interactive: true)
      @results = results
      @id_prefix = id_prefix
      @interactive = interactive
    end

    def view_template
      if @results.blank?
        # Nothing: the query is too short to have searched.
      elsif @results.any?
        div(class: "spotlight-listbox", **listbox_attributes) do
          deck_group
          shared_deck_group
          card_group
          tournament_group
          archetype_group
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
        index_path: decks_path(q: query), see_all_label: see_all_label(@results.deck_total, "deck"),
        id_prefix: @id_prefix, interactive: @interactive
      ) do |deck|
        option_row(
          dom_id: "#{@id_prefix}-option-deck-#{deck.id}",
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
        see_all_label: see_all_label(@results.shared_deck_total, "shared deck"),
        id_prefix: @id_prefix, interactive: @interactive
      ) do |deck|
        option_row(
          # A distinct prefix, so this group cannot collide with the one above even if the
          # exclusion in Search::Global is ever relaxed. Cheaper than relying on it.
          dom_id: "#{@id_prefix}-option-shared-deck-#{deck.id}",
          path: deck_path(deck),
          name: deck.name,
          meta: [ deck.format_label, deck.archetype&.name ].compact.join(" · ")
        )
      end
    end

    def card_group
      render ResultGroup.new(
        key: "cards", label: "CARDS", records: @results.cards, total: @results.card_total,
        index_path: cards_path(q: query), see_all_label: see_all_label(@results.card_total, "card"),
        id_prefix: @id_prefix, interactive: @interactive
      ) do |card|
        option_row(
          dom_id: "#{@id_prefix}-option-card-#{card.id}",
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
        see_all_label: see_all_label(@results.tournament_total, "tournament"),
        id_prefix: @id_prefix, interactive: @interactive
      ) do |tournament|
        option_row(
          dom_id: "#{@id_prefix}-option-tournament-#{tournament.id}",
          path: tournament_path(tournament),
          name: tournament.name,
          meta: "#{localize(tournament.date, format: :long)} · #{tournament.tier_label}"
        )
      end
    end

    def archetype_group
      render ResultGroup.new(
        key: "archetypes", label: "ARCHETYPES", records: @results.archetypes,
        total: @results.archetype_total, index_path: archetypes_path(q: query),
        see_all_label: see_all_label(@results.archetype_total, "archetype"),
        id_prefix: @id_prefix, interactive: @interactive
      ) do |archetype|
        option_row(
          # Its own prefix, like the shared-deck group above: these ids are derived from the
          # record id, and two groups sharing a prefix emit the same DOM id twice, which breaks
          # the keyboard walk. Archetype ids and Deck ids overlap freely.
          dom_id: "#{@id_prefix}-option-archetype-#{archetype.id}",
          path: archetype_path(archetype),
          name: archetype.name,
          meta: [ archetype.primary_card, archetype.secondary_card ].compact
            .map(&:printing_label).join(" · ")
        )
      end
    end

    def listbox_attributes
      @interactive ? { role: "listbox", aria_label: "Search results" } : { aria_label: "Search results" }
    end

    def option_attributes
      @interactive ? { role: "option", aria_selected: "false" } : {}
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
      a(id: dom_id, href: path, **option_attributes, class: "spotlight-option", data: { turbo_frame: "_top" }) do
        span(class: "spotlight-option-name") { name }
        span(class: "spotlight-option-meta") { meta }
      end
    end
  end
end
