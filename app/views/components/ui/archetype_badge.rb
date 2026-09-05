module Ui
  # An archetype as a badge, tinted by its lead card's energy type with a colour pip. Falls
  # back to the neutral archetype style when the type is unknown — which is always true of a
  # Trainer lead, since it has no energy type.
  #
  # Extracted from Decks::ClassificationBadges so the public badge row can reuse it: the two
  # rows show different things, but an archetype looks the same on both.
  class ArchetypeBadge < ApplicationComponent
    # `href` is optional and defaults to nil, which renders exactly what this component has
    # always rendered. It is opt-in rather than derived from the archetype because /archetypes
    # requires a session: a caller knows whether its own surface is behind one, and the badge
    # has no business asking a policy. Decks::ClassificationBadges is owner-only and always
    # passes it; Tournaments::Standings::Row passes it only when it has a viewer, since the
    # standings sheet is public; Decks::PublicBadges never does.
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
      a(href: @href) { badge }
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
