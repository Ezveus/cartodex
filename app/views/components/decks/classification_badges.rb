module Decks
  # Renders the classification of a deck (format, support, proxies) as a row
  # of badges. Shared between the deck list and the deck show header.
  class ClassificationBadges < ApplicationComponent
    # `live` is for the deck show page, where the allocation steppers change the very data the
    # proxy badge derives from without reloading the page. There the badge is always rendered and
    # merely hidden, so `deck-proxies` has an element to toggle. Everywhere else it is a plain
    # server-rendered badge that appears only when it applies.
    def initialize(deck:, over_allocated: false, live: false)
      @deck = deck
      @over_allocated = over_allocated
      @live = live
    end

    def view_template
      div(class: "deck-badges") do
        span(class: "badge badge-format") { @deck.format_label }
        render Ui::ArchetypeBadge.new(archetype: @deck.archetype) if @deck.archetype
        span(class: "badge") { "Physical" } if @deck.physical?
        span(class: "badge") { "TCG Live" } if @deck.tcg_live?
        proxies_badge
        span(class: "badge badge-warning") { "To review" } if @over_allocated
      end
    end

    private

    def proxies_badge
      has_proxies = @deck.has_proxies?
      return unless has_proxies || @live

      span(
        class: "badge badge-warning",
        hidden: !has_proxies,
        data: @live ? { deck_proxies_target: "badge" } : nil
      ) { "Proxies" }
    end
  end
end
