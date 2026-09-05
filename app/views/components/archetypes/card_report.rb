module Archetypes
  # What the recorded lists play. The categories arrive already ordered and already grouped by the
  # service — Pokémon, Supporter, Item, Stadium, Tool, Special Energy, Basic Energy, Other — and
  # this component adds no ordering of its own, so the display order stays a single decision made
  # in Archetypes::CardStats::CATEGORIES.
  class CardReport < ApplicationComponent
    def initialize(stats:, scope:)
      @stats = stats
      @scope = scope
    end

    def view_template
      section(class: "archetype-panel") do
        h2 { "Card report" }

        if @stats.any?
          fixed_core
          @stats.categories.each { |category| render Archetypes::CategorySection.new(category: category) }
        else
          empty_state
        end
      end
    end

    private

    # "N of 60 are settled, 60 − N are the list's own" — the one line that says how much of this
    # archetype is a decision and how much is not. It leads the report because it is the answer a
    # reader facing the deck wants before any individual card.
    def fixed_core
      p(class: "archetype-summary") do
        plain "Across "
        strong { "#{@stats.lists_count} #{'list'.pluralize(@stats.lists_count)}" }
        plain ", "
        strong { "#{@stats.fixed_core_cards} #{'card'.pluralize(@stats.fixed_core_cards)}" }
        plain " accounting for "
        strong { "#{@stats.fixed_core_copies} #{'copy'.pluralize(@stats.fixed_core_copies)}" }
        plain " are played by every list, always in the same number. Everything else is each "
        plain "list's own choice."
      end
    end

    # The suggestion is made only when there is something to suggest: pointing a reader at
    # "All formats" when the blended sample is just as empty wastes the click and reads as a bug.
    def empty_state
      p(class: "empty-state") do
        plain "No decklist recorded for this sample yet."
        plain " Lists exist under “All formats” — try that sample above." if elsewhere?
      end
    end

    def elsewhere?
      return false if @scope.all_formats?

      all_option = @scope.options.find { |option| option.value == MetagameScope::ALL }
      all_option&.lists_count.to_i.positive?
    end
  end
end
