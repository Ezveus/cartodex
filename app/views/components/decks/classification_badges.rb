module Decks
  # Renders the classification of a deck (format, support, proxies) as a row
  # of badges. Shared between the deck list and the deck show header.
  class ClassificationBadges < ApplicationComponent
    # `live` is for the deck show page, where the allocation steppers change the very data the
    # proxy badge derives from without reloading the page. There the badge is always rendered and
    # merely hidden, so `deck-proxies` has an element to toggle. Everywhere else it is a plain
    # server-rendered badge that appears only when it applies.
    # `linked` makes the archetype badge a link to that archetype's metagame page, and it is a
    # call-site decision because only the call site knows whether this row already sits inside an
    # anchor. Decks::DeckCard wraps its whole card body in `a.deck-item-link`, and an `<a>` inside
    # an `<a>` is not merely invalid: an HTML5 parser runs the adoption-agency algorithm on the
    # second start tag and closes the outer one first, so on /decks the deck link ended just after
    # the `<h2>` and the description and card count fell outside any link — clicking them opened
    # nothing. Measured on the real page, and invisible to the suite, because `assert_select`
    # parses with Nokogiri's HTML4 parser, which nests anchors happily. Decks::HeaderFrame renders
    # this row inside a plain div and is the only caller that can carry the link.
    def initialize(deck:, over_allocated: false, live: false, linked: false)
      @deck = deck
      @over_allocated = over_allocated
      @live = live
      @linked = linked
    end

    def view_template
      div(class: "deck-badges") do
        span(class: "badge badge-format") { @deck.format_label }
        # Owner views only — this component is never rendered on a public surface.
        span(class: "badge") { "Shared" } if @deck.shared?
        # This row is owner-only and therefore always behind a session, which is what /archetypes
        # needs — but see `linked` above for why the link is still the call site's decision.
        # Decks::PublicBadges, the row a visitor can reach, has no link at all.
        #
        # The route helper is called as a module method, exactly as Decks::DeckCard calls
        # deck_path: Decks::ImportJob renders that card — and this row inside it — with a bare
        # Phlex `.call`, and Phlex::Rails::Helpers::Routes resolves a _path helper through
        # url_options, which delegates to a view_context that does not exist outside a request.
        archetype_badge
        span(class: "badge") { "Physical" } if @deck.physical?
        span(class: "badge") { "TCG Live" } if @deck.tcg_live?
        proxies_badge
        span(class: "badge badge-warning") { "To review" } if @over_allocated
      end
    end

    private

    def archetype_badge
      return unless @deck.archetype

      href = Rails.application.routes.url_helpers.archetype_path(@deck.archetype) if @linked
      render Ui::ArchetypeBadge.new(archetype: @deck.archetype, href: href)
    end

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
