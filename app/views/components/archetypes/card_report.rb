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
          range_note unless single_list?
          overlap_note if role_mode?
          provenance_note if role_mode? && @stats.unconfirmed_roles?
          reprint_note if @stats.reprints?
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
        @scope.archetype, pool: pool_param, group: mode, venue: venue_param
      )
    end

    def pool_param
      @scope.all_formats? ? MetagameScope::ALL : @scope.pool&.id
    end

    # Read off the scope, never off params, for the reason `pool_param` is — and here it is what
    # tells a clamp recorded in the Result apart from one applied to the relation alone: a link
    # rebuilt from the parameter would carry a dead venue into every copy of the URL. Nil at
    # `:all`, so a default never enters the query string; `archetype_path` drops a nil parameter.
    def venue_param
      @scope.venue == :all ? nil : @scope.venue
    end

    # The third sentence of the same family, and the one the copies figures make necessary in
    # **both** modes. It carries two claims, and each was measured before it was written.
    #
    # It says *these figures* rather than *these ranges*, because the range is not the column that
    # invites the addition — the **mode** is. Measured over the eight samples the production data
    # offers, the modes sum to 60 or 61 every time, so a reader adding that column lands on a
    # plausible 60-card profile; and on the three largest samples that profile is played by
    # **zero** lists. The ranges are the honest half of the same trap (default pool: minima 53,
    # maxima 69, over lists that all play exactly 60), and naming only them would disarm the
    # column that is nearly harmless while leaving the one that looks right.
    #
    # And it names the zeros rule, because the page shows both rules a line apart and explains
    # neither. TEF-CRI renders `Stadium · 1 card · 0-4 copies` directly above that section's only
    # card at `95.5% of lists · 3-4 copies`: one card, two different floors, and the reader can
    # only reconstruct the 0 by noticing that 95.5 is not 100.
    #
    # The card count is the third figure the sentence has to separate: it is over the whole
    # sample, so all-formats reads `Pokémon · 32 cards · 16-23 copies` — a contradiction if the
    # two are taken as facts about one list.
    #
    # Withheld at one list, where there is no range to disclaim: every section prints an exact
    # number and adding them up genuinely gives the list. Deliberately not because the sections
    # partition it — in role mode they still do not, a single list carrying one dual-role card
    # already summing past 60 — but that is the overlap note's sentence, and it renders at one
    # list too.
    def range_note
      p(class: "archetype-range-note") do
        "Each heading gives the copies one list plays of that section, and a list playing none " \
          "of it counts as zero here — unlike a card's own range below, which covers only the " \
          "lists that play it. Those figures belong to different lists, so adding them up across " \
          "sections describes no list, and the card count beside them is over the whole sample " \
          "rather than over one list."
      end
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

    # A rule's guess and a human's decision are the same row to everything below this line, and
    # the report has no way to show the difference card by card without saying it about the
    # sections a reader is already asked to read carefully. So it says the ratio once, at the top,
    # in the register of the overlap note: on the production data the day this shipped, 714 of 714
    # assignments were proposals and the method note underneath still read "a person decides".
    def provenance_note
      total = @stats.proposed_roles + @stats.decided_roles

      p(class: "archetype-provenance-note") do
        plain "#{@stats.proposed_roles} of the #{total} roles below "
        plain "#{@stats.proposed_roles == 1 ? 'is a proposal a rule made' : 'are proposals a rule made'} "
        plain "from the card's own text, which nobody has confirmed yet."
      end
    end

    # The sentence the set code on a card row makes necessary, and the fourth on this page written
    # to stop a reader taking a figure for something it is not.
    #
    # The report is keyed on the printing-independent card key, so a row can name one printing
    # while its share, its copies and its `fixed` flag count every reprint of that card. Measured
    # on the production data: 16 distinct card keys fold two printings a list actually played, and
    # the worst of them is `Ultra Ball (MEG 131)` reading "100% of lists (154)" where 56 of those
    # 154 lists played SVI 196 instead — a 36-point gap between the line and the code on it. Two
    # such rows also carry the `fixed` flag, whose title says "played by every list, always in the
    # same number": true of Fezandipiti ex, false of the SFA 38 printed beside it — which is why
    # the sentence names the flag as well as the two figures. It is the one of the three that is
    # not itself a number, so a sentence covering only "the share and the copies" left the reader
    # to decide which of the two it was derived from, and `Entry#fixed?` is both.
    #
    # It renders only where the sample holds an instance, the rule the pool note follows: a
    # disclaimer on every page is a disclaimer nobody reads, and 242 of the 246 reachable samples
    # have nothing to disclaim. Withheld before this feature there was nothing to say — the row
    # named no printing, so nothing on it was about one.
    #
    # Placed after the provenance note so `.archetype-range-note + .archetype-overlap-note` keeps
    # its adjacency; that selector is the one thing in the archetype CSS block that buys weight.
    def reprint_note
      count = @stats.reprinted_cards

      p(class: "archetype-reprint-note") do
        plain "#{count} #{'card'.pluralize(count)} below #{count == 1 ? 'is' : 'are'} played in "
        plain "more than one printing, and the code names whichever of them more lists chose than "
        plain "any other. Everything beside it — its share, its copies, and whether it is marked "
        plain "“fixed” — counts every printing of that card, so some of the lists counted there "
        plain "played a different one."
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
    #
    # Both axes, and both counted in the state the click would actually produce. The one form
    # carries the venue along with a pool change, so "try All formats" has to be true *of this
    # venue* — `options`' own "All formats" count is venue-independent and would promise lists the
    # current venue may not hold. And the venue is the other click available: where a pool has
    # placements and typed lists on one side only, that is the direction worth naming, and
    # `options` cannot see it at all. Reachable by design rather than observed — measured, 0
    # (pool, venue) cells hold standings and no list today — but "TEF-PBL — 0 lists" is a shape
    # this page renders on purpose.
    def empty_state
      p(class: "empty-state") do
        plain "No decklist recorded for this sample yet."
        plain " Lists exist under “All formats” — try that sample above." if lists_in_other_pool?
        plain " Lists exist under “All” venues — try that beside it." if lists_in_other_venue?
      end
    end

    def lists_in_other_pool?
      !@scope.all_formats? && @scope.all_formats_lists_count.positive?
    end

    def lists_in_other_venue?
      return false if @scope.venue == :all

      all_venues = @scope.venue_options.find { |option| option.value == MetagameScope::ALL }
      all_venues&.lists_count.to_i.positive?
    end
  end
end
