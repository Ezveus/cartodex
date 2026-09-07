module Archetypes
  # Which sample the page is reporting on, and how much that sample is worth.
  #
  # Six rules meet here, and all six are the design's, not this component's taste. Each is a
  # predicate on Archetypes::MetagameScope::Result rather than a condition assembled here, because
  # every one of them is a fact about the sample and the page must not compute it twice:
  #
  #   * the control is dropped entirely when `selectable?` is false. A <select> holding one option
  #     is not a choice, and neither is one holding "TEF-PBL — 1 list" beside
  #     "All formats — 1 list": two labels over one sample, which reads as a filter that does not
  #     filter. Measured on the production data, that is the majority of archetypes with any
  #     standings at all.
  #   * the pool note explains a distinction — a list counted under "All formats" and under no
  #     pool — that only exists when `unpooled?`. Printed otherwise it sends the reader looking
  #     for rows the sample does not hold. It is conjoined with `selectable?` rather than implied
  #     by it: an archetype whose every standing sits outside Standard is `unpooled?` and still
  #     has "All formats" as its only option, so the note would be describing a choice the page
  #     is not offering.
  #   * the small-sample notice's closing clause promises a fuller sample one click away, so it
  #     is printed only when `fuller_sample_available?` — an archetype already on its largest
  #     sample would otherwise be told to click for more of nothing.
  #   * the venue control is dropped when `venue_selectable?` is false, on exactly the pool
  #     axis's reasoning: "All — 20 lists" beside "Online — 20 lists" is two labels for one
  #     sample. Measured, that is the majority shape — of the 59 (archetype, pool) buckets in
  #     production, 12 are paper-only and 23 online-only, so the control is absent from 35.
  #   * the venue note says that the Sample counts span both venues, printed only when a venue is
  #     chosen and the pool control is offered. The pool labels are deliberately stable, so the
  #     number beside the pool is the pool's whole size while the report covers one half of it —
  #     and the clamp does not rescue that, since it fires only where the target cell is empty.
  #   * the online note names what is left of the blend once the reader has chosen a sample, and
  #     its second sentence — the report counts both kinds together — prints only when the sample
  #     really does hold both. Unconditional, it was false on 23 of the 48 archetypes carrying a
  #     list, every one of which opens on an all-online sample and was told the report counted
  #     paper lists that do not exist. `Archetypes::PerformancePanel` carries the same rule over
  #     its own population, and had the same defect.
  #
  # The notice itself is not decoration. The default view of a freshly imported archetype is very
  # often exactly this case — the measured one opens on a pool holding three lists, where every
  # percentage on the page below is 33, 67 or 100.
  #
  # The form is a GET back onto the same page, so the chosen sample survives a reload and a
  # copied link; `card-filter` is what submits it on change, which is the same controller both
  # deck listings' filter bars use.
  class SampleSelector < ApplicationComponent
    def initialize(scope:, grouping: :type)
      @scope = scope
      @grouping = grouping
    end

    def view_template
      # Nothing to say at all when the archetype has one sample, it is not a small one, and it is
      # all paper — an empty flex wrapper would still take the block's margin above the panel
      # below it. `online_lists?` is a third reason to have something to say, and not a refinement
      # of the first two: an archetype whose every standing sits in one pool is not `selectable?`
      # and a sixteen-list sample is not `small_sample?`, which is exactly the shape one online
      # import produces, so without it the blend would be named nowhere on this page.
      return unless @scope.selectable? || @scope.venue_selectable? ||
                    @scope.small_sample? || @scope.online_lists?

      div(class: "archetype-sample") do
        selector
        venue_note
        pool_note
        online_note
        small_sample_notice
      end
    end

    private

    # One form, two selects, and three separate guards. The form renders when *either* axis is a
    # choice — `||` and not `&&`, because an archetype with one pool and both venues is 15 of the
    # 24 blended ones and would otherwise lose the form entirely — while each select answers only
    # for its own axis: widening the Sample select to the form's guard renders a
    # `<select name="pool">` of one option, which is the thing `Result#selectable?` exists to
    # prevent, and widening the Venue select to `selectable?` offers "Online — 0 lists" on an
    # archetype that has never had an online result.
    #
    # No new CSS, and that is measured rather than assumed: `.deck-filters` is already
    # `display: flex; flex-wrap: wrap; gap: .5rem` and `.archetype-sample-label` is already the
    # flex item carrying a label and its select, so two of them sit side by side above the
    # breakpoint and stack below it.
    def selector
      return unless @scope.selectable? || @scope.venue_selectable?

      form(action: archetype_path(@scope.archetype), method: "get", class: "deck-filters",
           data: { controller: "card-filter" }) do
        # The grouping rides along, because this form replaces the whole query string: without it
        # a reader in role mode who changes the sample is silently returned to type mode, which is
        # the same loss Archetypes::CardReport's links go to trouble to prevent on the other axis.
        input(type: "hidden", name: "group", value: "role") if @grouping == :role
        pool_select
        venue_select
      end
    end

    # The label wraps the select rather than pointing at it: Ui::FilterSelect emits no id, and an
    # explicit `for=` naming one that does not exist associates nothing at all.
    def pool_select
      return unless @scope.selectable?

      label(class: "archetype-sample-label") do
        span { "Sample" }
        render Ui::FilterSelect.new(name: "pool", options: options, selected: selected)
      end
    end

    # `selected:` is read off the scope and is not optional. Omitted, Ui::FilterSelect marks no
    # option and the browser pre-selects the first — "All" — above a report showing Online. That
    # is the trap TournamentStanding's division select paid for once: a select built without the
    # record's own value renders no matching option, the browser picks the first, and a member
    # silently refiles a result under it.
    def venue_select
      return unless @scope.venue_selectable?

      label(class: "archetype-sample-label") do
        span { "Venue" }
        render Ui::FilterSelect.new(name: "venue", options: venue_options,
                                    selected: @scope.venue.to_s)
      end
    end

    def options
      @scope.options.map { |option| [ option.label, option.value ] }
    end

    def venue_options
      @scope.venue_options.map { |option| [ option.label, option.value ] }
    end

    def selected
      @scope.all_formats? ? MetagameScope::ALL : @scope.pool&.id.to_s
    end

    # The Sample select's own label says "Sample", so its selected option reads as an assertion
    # about the sample the page is showing — and once a venue is chosen it is not one. The pool
    # options are venue-independent by design (see MetagameScope#options: recounting them inside
    # the current venue makes labels shift under the reader between loads and produces options
    # reading "SVI-BLK — 0 lists"), so the number beside the pool is the pool's whole size while
    # the report below covers one half of it.
    #
    # The clamp does **not** rescue that, which is what an earlier version of this comment claimed
    # and what the design record argued from: it fires only where the target cell is empty, so it
    # covers exactly the options that cannot lie. Measured on the production data, 78 of the 171
    # rendered pool options do not deliver their own label on a click, and "All formats" is
    # structurally on the wrong side of it — it always holds a standing in the current venue,
    # since otherwise the reader would not be in that venue. Worst measured gap: Dragapult ex at
    # `pool=all&venue=online`, "All formats — 174 lists" selected above a 20-list report.
    #
    # So the page says it, in the register it says everything else it cannot compute away. This is
    # the cheaper half of the trade; the alternative that makes the label literally true is to give
    # the Sample select its own form so that changing the pool resets the venue, which is a
    # different product decision about what a click does and is left to the owner.
    def venue_note
      return unless @scope.venue != :all && @scope.selectable?

      count = @scope.lists_count

      p(class: "archetype-sample-note") do
        plain "The Sample counts above are over both venues. This report covers the "
        strong { "#{count} #{'list'.pluralize(count)}" }
        plain " of the venue selected beside it."
      end
    end

    # Said rather than left to be discovered — but only where there is something to discover. A
    # non-Standard event carries no pool by design, so a GLC or an Expanded list is invisible
    # under every pool option and appears only in the blended one. Where this archetype has no
    # such event, the sentence describes an absence nothing on the page can show.
    #
    # `unpooled_in_sample?` and not `unpooled?`, which is the venue-independent one `selectable?`
    # needs: an archetype whose only non-Standard event is paper prints this under Online about a
    # list that venue does not hold at all — the sample counts it nowhere, not "under All formats
    # only". Measured, 21 states over 7 archetypes.
    def pool_note
      return unless @scope.unpooled_in_sample? && @scope.selectable?

      p(class: "archetype-sample-note") do
        "Events outside Standard carry no pool, so their lists are counted under “All formats” only."
      end
    end

    # About lists and not standings, because this sits above the card report and the card report's
    # denominator is lists. The performance panel names the same blend over its own population.
    #
    # The second sentence prints only when the sample actually holds both kinds. Unconditional, it
    # was false on 23 of the 48 archetypes carrying a list — every one of which opens on a sample
    # with no paper list at all, so 23 production pages claimed to count paper lists that do not
    # exist — and it would have been false again under `venue=online`. Under `venue=paper` the
    # whole note withholds itself through the guard above, which is right: the Venue select
    # already reads "Paper — 98 lists".
    def online_note
      return unless @scope.online_lists?

      count = @scope.online_lists_count

      p(class: "archetype-sample-note") do
        if @scope.blended?
          plain "#{count} of these #{@scope.lists_count} lists "
          plain "#{count == 1 ? 'comes' : 'come'} from an online tournament. "
          plain "The card report below counts online and paper lists together."
        else
          plain "Every list in this sample comes from an online tournament."
        end
      end
    end

    def small_sample_notice
      return unless @scope.small_sample?

      p(class: "archetype-notice") do
        plain "Small sample: every percentage below is computed over "
        strong { "#{@scope.lists_count} #{'list'.pluralize(@scope.lists_count)}" }
        # Singular agreement, because the venue axis made a one-list sample ordinary: 18 states
        # over the production data render this at exactly one list, most of them paper halves.
        plain ". That describes what "
        plain @scope.lists_count == 1 ? "that list" : "those lists"
        plain " did and supports no conclusion about the archetype"
        plain @scope.fuller_sample_available? ? " — a fuller sample may be one click away above." : "."
      end
    end
  end
end
