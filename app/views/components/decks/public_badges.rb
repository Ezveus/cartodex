module Decks
  # The badges a visitor may see: the format and the archetype, and nothing else.
  #
  # Deliberately not ClassificationBadges with a flag. "Physical" and "TCG Live" say how the
  # owner plays the deck and are of no use to a reader; "Proxies" and "To review" report what
  # the owner does and does not own, which is collection data reached through a deck.
  class PublicBadges < ApplicationComponent
    # `linked:` for the reason Decks::ClassificationBadges takes it, and it defaults to **false**
    # for the same reason too: of the three surfaces that render this component, two put it
    # inside an anchor of their own — Decks::DeckCard's `a.deck-item-link` (the shared-decks
    # grid) and Home::DashboardView's showcase tile — and an `<a>` within an `<a>` makes an
    # HTML5 parser close the outer one at the second start tag. Measured on the shared grid
    # before this keyword existed: the deck's own link ended after its `<h2>`, and the
    # description, the card count *and* the whole badge row fell outside it. `assert_select`
    # parses HTML4 and nests anchors happily, so the guard is two controller tests reading
    # Nokogiri::HTML5 — and the emptiness half of those cannot stand alone, since the parser
    # makes the escaped anchor a *sibling*: they assert containment first.
    #
    # Decks::PublicShowView is the one caller that opts in. /archetypes is public, so a reader
    # who can see the tag can read the report behind it.
    def initialize(deck:, linked: false)
      @deck = deck
      @linked = linked
    end

    def view_template
      div(class: "deck-badges") do
        span(class: "badge badge-format") { @deck.format_label }
        render Ui::ArchetypeBadge.new(archetype: @deck.archetype, href: archetype_href) if @deck.archetype
      end
    end

    private

    # `Rails.application.routes.url_helpers` and not `archetype_path`, for the reason
    # Decks::ClassificationBadges uses it: this component is rendered by a bare Phlex `.call` in
    # Styleguide::PageView and in component tests, where Phlex::Rails' Routes delegates to a nil
    # view_context and raises.
    def archetype_href
      return nil unless @linked

      Rails.application.routes.url_helpers.archetype_path(@deck.archetype)
    end
  end
end
