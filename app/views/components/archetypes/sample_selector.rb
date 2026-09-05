module Archetypes
  # Which sample the page is reporting on, and how much that sample is worth.
  #
  # Three rules meet here, and all three are the design's, not this component's taste. Each is a
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
  #
  # The notice itself is not decoration. The default view of a freshly imported archetype is very
  # often exactly this case — the measured one opens on a pool holding three lists, where every
  # percentage on the page below is 33, 67 or 100.
  #
  # The form is a GET back onto the same page, so the chosen sample survives a reload and a
  # copied link; `card-filter` is what submits it on change, which is the same controller both
  # deck listings' filter bars use.
  class SampleSelector < ApplicationComponent
    def initialize(scope:)
      @scope = scope
    end

    def view_template
      # Nothing to say at all when the archetype has one sample and it is not a small one — an
      # empty flex wrapper would still take the block's margin above the panel below it.
      return unless @scope.selectable? || @scope.small_sample?

      div(class: "archetype-sample") do
        selector
        pool_note
        small_sample_notice
      end
    end

    private

    def selector
      return unless @scope.selectable?

      form(action: archetype_path(@scope.archetype), method: "get", class: "deck-filters",
           data: { controller: "card-filter" }) do
        # The label wraps the select rather than pointing at it: Ui::FilterSelect emits no id,
        # and an explicit `for=` naming one that does not exist associates nothing at all.
        label(class: "archetype-sample-label") do
          span { "Sample" }
          render Ui::FilterSelect.new(name: "pool", options: options, selected: selected)
        end
      end
    end

    def options
      @scope.options.map { |option| [ option.label, option.value ] }
    end

    def selected
      @scope.all_formats? ? MetagameScope::ALL : @scope.pool&.id.to_s
    end

    # Said rather than left to be discovered — but only where there is something to discover. A
    # non-Standard event carries no pool by design, so a GLC or an Expanded list is invisible
    # under every pool option and appears only in the blended one. Where this archetype has no
    # such event, the sentence describes an absence nothing on the page can show.
    def pool_note
      return unless @scope.unpooled? && @scope.selectable?

      p(class: "archetype-sample-note") do
        "Events outside Standard carry no pool, so their lists are counted under “All formats” only."
      end
    end

    def small_sample_notice
      return unless @scope.small_sample?

      p(class: "archetype-notice") do
        plain "Small sample: every percentage below is computed over "
        strong { "#{@scope.lists_count} #{'list'.pluralize(@scope.lists_count)}" }
        plain ". That describes what those lists did and supports no conclusion about the archetype"
        plain @scope.fuller_sample_available? ? " — a fuller sample may be one click away above." : "."
      end
    end
  end
end
