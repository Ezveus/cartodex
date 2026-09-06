module Archetypes
  # What the recorded lists play. The sections arrive already ordered and already grouped by the
  # service — by card type (Pokémon, Supporter, Item, Tool, Stadium, Special Energy, Basic Energy,
  # Other) or by what the card does (the role vocabulary, then "No role recorded") — and this
  # component adds no ordering of its own, so the display order stays a single decision made in
  # Archetypes::CardStats.
  #
  # The mode control lives here and not in Archetypes::SampleSelector, which is dropped entirely
  # when `selectable?` is false: a page whose archetype has one sample would then offer no way back
  # out of role mode. Which mode is showing is read off the result rather than passed in beside it,
  # so the links cannot name a grouping other than the one the sections below them were built with.
  class CardReport < ApplicationComponent
    # The two groupings, in the order the header offers them: the report's own default first.
    MODES = [ [ :type, "Type" ], [ :role, "Role" ] ].freeze

    def initialize(stats:, scope:)
      @stats = stats
      @scope = scope
    end

    def view_template
      section(class: "archetype-panel") do
        header

        if @stats.any?
          summary
          overlap_note if role_mode?
          @stats.categories.each do |category|
            render Archetypes::CategorySection.new(category: category, single_list: single_list?)
          end
        else
          empty_state
        end
      end
    end

    private

    def role_mode? = @stats.role_grouping?

    def header
      div(class: "archetype-report-header") do
        h2 { "Card report" }
        # Withheld on an empty sample: both modes render the same "no decklist recorded" line, so
        # the control would be a click that changes the URL and not the page.
        mode_links if @stats.any?
      end
    end

    def mode_links
      div(class: "archetype-report-modes") do
        span(class: "archetype-report-modes-label") { "Group by" }
        MODES.each { |mode, label| mode_link(mode, label) }
      end
    end

    # The current mode stays a link — it is a tab, and a tab that cannot be clicked reads as
    # disabled — so what says which one is showing is `aria-current` and a modifier class, not the
    # absence of an anchor.
    def mode_link(mode, label)
      current = role_mode? == (mode == :role)
      classes = [ "archetype-report-mode" ]
      classes << "archetype-report-mode--current" if current

      a(href: path_for(mode), class: classes.join(" "),
        aria_current: ("page" if current)) { label }
    end

    # A plain anchor over the routes module, not `link_to` with `archetype_path`: both of those
    # resolve through a view_context, which does not exist when this component is rendered by a
    # bare `.call` — the trap Ui::ArchetypeBadge documents, and the reason this component has a
    # unit test at all.
    #
    # The sample re-emitted is the one the page is **showing**, taken from the scope and never from
    # `params[:pool]`. A malformed `?pool[]=junk` is the case where the two differ: the scope fell
    # back to the default pool, and a link built from the parameter would carry the junk back into
    # the next request and into every copy of that link. The component is handed no parameters at
    # all, which makes that structural rather than a convention.
    def path_for(mode)
      Rails.application.routes.url_helpers.archetype_path(
        @scope.archetype, pool: pool_param, group: mode
      )
    end

    def pool_param
      @scope.all_formats? ? MetagameScope::ALL : @scope.pool&.id
    end

    # The sentence a reader cannot infer from the sections themselves, in the register of the one
    # that stops them taking Hoothoot's printings for a decomposition. The overlap is half the
    # vocabulary rather than a corner case — Iono is draw and disruption, Prime Catcher is gust and
    # switch — so the sections genuinely describe more cards between them than a list holds, and a
    # reader adding them up concludes the wrong thing about every number on the page.
    def overlap_note
      p(class: "archetype-overlap-note") do
        "A card is listed under every role it plays, so a card with two roles appears twice and " \
          "these sections add up to more than the 60 cards of a list."
      end
    end

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
