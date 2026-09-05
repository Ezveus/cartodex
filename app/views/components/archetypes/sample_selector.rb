module Archetypes
  # Which sample the page is reporting on, and how much that sample is worth.
  #
  # Two rules meet here, and both are the design's, not this component's taste:
  #
  #   * the control is dropped entirely when `selectable?` is false. A <select> holding one option
  #     is not a choice, and a filter bar that cannot filter reads as a page that lost its data.
  #   * the small-sample notice is not decoration. The default view of a freshly imported
  #     archetype is very often exactly this case — the measured one opens on a pool holding three
  #     lists, where every percentage on the page below is 33, 67 or 100.
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

    # Said rather than left to be discovered. A non-Standard event carries no pool by design —
    # only Standard rotates — so a GLC or an Expanded list is invisible under every pool option
    # and appears only in the blended one.
    def pool_note
      return unless @scope.selectable?

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
        plain @scope.selectable? ? " — a fuller sample may be one click away above." : "."
      end
    end
  end
end
