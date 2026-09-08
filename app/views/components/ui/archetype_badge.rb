module Ui
  # An archetype as a badge, tinted by its lead card's energy type with a colour pip. Falls
  # back to the neutral archetype style when the type is unknown — which is always true of a
  # Trainer lead, since it has no energy type.
  #
  # Extracted from Decks::ClassificationBadges so the public badge row can reuse it: the two
  # rows show different things, but an archetype looks the same on both.
  class ArchetypeBadge < ApplicationComponent
    # `href` is optional and defaults to nil, which renders exactly what this component has
    # always rendered. It stays opt-in rather than derived from the archetype, but the reason
    # changed when /archetypes went public: it is no longer "does this reader have a session"
    # — every caller's target is now reachable by anybody — it is **"is this badge already
    # inside an anchor"**, which only the call site can know and which no policy could answer.
    # Decks::ClassificationBadges takes `linked:` because Decks::DeckCard wraps its row in
    # `a.deck-item-link`; Decks::PublicBadges takes it for the same reason on two of its three
    # surfaces; Tournaments::Standings::Row passes an href unconditionally, its cell being a
    # plain div.
    def initialize(archetype:, href: nil)
      @archetype = archetype
      @href = href
    end

    def view_template
      return badge if @href.nil?

      # A plain `a`, not `link_to`, for the reason Decks::DeckCard writes its own anchor by
      # hand: Decks::ImportJob broadcasts a DeckCard — and through it these badges — with a bare
      # Phlex `.call`, outside any request. Phlex::Rails::Helpers::LinkTo delegates to a nil
      # view_context there and raises NoMethodError, which would have turned every import of a
      # deck the detector tagged into a failed broadcast. An element takes an href with no
      # url_for involved, so this renders in a request and out of one alike.
      #
      # It needs no class of its own: .badge is inline-block and .badge-energy is inline-flex,
      # and a text decoration propagated from an ancestor is never drawn inside an atomic
      # inline-level box — so the anchor adds no underline, and the badge's own rule keeps its
      # colour. Wrapping rather than moving the badge classes onto the <a> is what keeps the
      # href-less rendering byte-identical.
      #
      # `_top` is not a call-site decision the way Decks::ActionsDropdown's `edit_frame` is: this
      # link always navigates to a different page, and every surface that passes an href renders
      # this row inside a Turbo Frame — Decks::HeaderFrame inside `deck-header`, and the standings
      # row inside a broadcast target. Frame-scoped, a click fetches /archetypes/N, finds no frame
      # of that id in the response, and replaces the deck header with Turbo's missing-frame error
      # instead of going anywhere. Decks::DeckCard breaks its own link out for the same reason.
      a(href: @href, data: { turbo_frame: "_top" }) { badge }
    end

    private

    def badge
      slug = @archetype.primary_energy_type&.downcase

      if slug
        span(class: "badge badge-energy badge-#{slug}") do
          span(class: "badge-pip")
          plain @archetype.name
        end
      else
        span(class: "badge badge-archetype") { @archetype.name }
      end
    end
  end
end
