module Ui
  # An archetype as a badge, tinted by its lead card's energy type with a colour pip. Falls
  # back to the neutral archetype style when the type is unknown — which is always true of a
  # Trainer lead, since it has no energy type.
  #
  # Extracted from Decks::ClassificationBadges so the public badge row can reuse it: the two
  # rows show different things, but an archetype looks the same on both.
  class ArchetypeBadge < ApplicationComponent
    def initialize(archetype:)
      @archetype = archetype
    end

    def view_template
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
