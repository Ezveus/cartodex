module Decks
  class DeckCard < ApplicationComponent
    # `public_listing` is one switch for the three things on this row a stranger must not get:
    # the owner's badges, the foil flag (which prints the win rate — the record stays private),
    # and the compare checkbox (whose controller a public page does not carry). One keyword
    # rather than three because they are one decision, and the next caller cannot get one of
    # them wrong.
    def initialize(deck:, with_actions: true, over_allocated: false, public_listing: false)
      @deck = deck
      @with_actions = with_actions
      @over_allocated = over_allocated
      @public_listing = public_listing
    end

    def view_template
      # Not computed on a public listing: hot? reads deck_results, which the shared index does
      # not preload, and its answer would be a leak anyway.
      hot = !@public_listing && @deck.hot?
      item_class = hot ? "deck-item is-foil" : "deck-item"

      div(class: item_class, id: "deck-#{@deck.id}") do
        type_stripe
        if hot
          div(class: "deck-foil-sheen", aria_hidden: "true")
          span(class: "deck-hot-flag") { "★ #{(@deck.win_rate * 100).round}%" }
        end
        compare_checkbox unless @public_listing
        # The decks index renders this card inside the deck_results Turbo Frame, so
        # every link in it is frame-scoped by default and would swap the grid for a
        # "Content missing" error. Break out to the top level instead.
        a(href: Rails.application.routes.url_helpers.deck_path(@deck), class: "deck-item-link", data: { turbo_frame: "_top" }) do
          h2 { @deck.name }
          # Physical, TCG Live, Proxies and Shared all describe how the owner keeps the deck;
          # the first three of those read the collection through it. A public listing gets the
          # format and the archetype only.
          if @public_listing
            render Decks::PublicBadges.new(deck: @deck)
          else
            render Decks::ClassificationBadges.new(deck: @deck, over_allocated: @over_allocated)
          end
          p(class: "deck-description") { @deck.description } if @deck.description.present?
          p(class: "deck-card-count") { "#{@deck.deck_cards.sum(&:quantity)} cards" }
        end
        if @with_actions
          div(class: "deck-item-actions") do
            # Same reason as the link above: Edit must leave the frame here. The
            # deck show page passes Decks::HeaderFrame::FRAME_ID instead, so the
            # target stays a call-site decision rather than a hardcoded "_top".
            render Decks::ActionsDropdown.new(deck: @deck, edit_frame: "_top")
          end
        end
      end
    end

    private

    # A thin bar at the top edge of the card, coloured by the deck's energy
    # type(s). Two types blend into a gradient; one fills solid.
    def type_stripe
      colors = @deck.energy_types.filter_map { |t| Card::TYPE_TOKENS[t] }.map { |token| "var(--#{token})" }
      return if colors.empty?

      background = colors.one? ? colors.first : "linear-gradient(90deg, #{colors.first}, #{colors.last})"
      div(class: "deck-stripe", style: "background: #{background}")
    end

    def compare_checkbox
      input(
        type: "checkbox",
        class: "deck-compare-checkbox",
        value: @deck.key,
        aria_label: "Select #{@deck.name} to compare",
        data: { deck_compare_target: "checkbox", action: "deck-compare#toggle" }
      )
    end
  end
end
