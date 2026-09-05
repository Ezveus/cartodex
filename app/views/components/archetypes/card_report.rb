module Archetypes
  # What the recorded lists play. The categories arrive already ordered and already grouped by the
  # service — Pokémon, Supporter, Item, Tool, Stadium, Special Energy, Basic Energy, Other — and
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
          summary
          @stats.categories.each do |category|
            render Archetypes::CategorySection.new(category: category, single_list: single_list?)
          end
        else
          empty_state
        end
      end
    end

    private

    # One list is not a sample of itself. `core` is `inclusion_count == lists_count`, so at one
    # list every card in it is "played by every list", and every quantity is "always the same
    # number" for want of a second number to differ from. The settled-core sentence below would
    # therefore republish the entire decklist under the word "fixed" and present it as a
    # measurement — on the production data, archetype 47 read "25 cards accounting for 60 copies",
    # which is the list. This is also why no row carries a `fixed` flag at this size; the flag
    # would say something about the sample rather than about the archetype, so the page says it
    # once here instead.
    def single_list? = @stats.lists_count == 1

    def summary
      single_list? ? single_list_summary : fixed_core
    end

    def single_list_summary
      p(class: "archetype-summary") do
        "Only one list is recorded for this sample, so there is nothing to compare it against — " \
          "what follows is that list."
      end
    end

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
        # The verb agrees with the card count, which is genuinely 1 often enough to matter: two
        # lists agreeing on exactly one card reads "1 card accounting for 4 copies is played".
        plain " #{@stats.fixed_core_cards == 1 ? 'is' : 'are'} played by every list, always in "
        plain "the same number. Everything else is each list's own choice."
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
