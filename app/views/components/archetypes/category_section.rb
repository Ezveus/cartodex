module Archetypes
  # One category of the report. The card count in the heading counts *printings*, which is
  # CategoryGroup#cards_count's own definition — three Hoothoots are three cards a player may have
  # to recognise, even though they are one name in the list below.
  #
  # Beside it, how many copies of the category a list plays — a different number, and one the
  # per-card figures cannot produce: summing their minima and maxima counts cards no single list
  # plays together, and on the production data that reads 39-57 where the truth is 16-23.
  class CategorySection < ApplicationComponent
    include Archetypes::CopiesText

    # `single_list` travels straight through to the rows: at one list the "fixed" flag is a
    # statement about the sample size and not about the archetype, and Archetypes::CardReport has
    # already said it once for the whole report. Defaulted so the styleguide, which renders rows
    # standing alone, keeps showing the flag it is there to show.
    def initialize(category:, single_list: false)
      @category = category
      @single_list = single_list
    end

    def view_template
      div(class: "archetype-category") do
        div(class: "archetype-category-header") do
          h3 { @category.label }
          meta
        end

        ul(class: "archetype-card-list") do
          @category.name_groups.each do |group|
            render Archetypes::NameGroupRow.new(group: group, single_list: @single_list)
          end
        end
      end
    end

    private

    # One wrapper and not two children of the header, and that wrapper is load-bearing.
    # `.archetype-category-header` is `display: flex; justify-content: space-between`, so a third
    # child is not placed beside the second — it is spread to the far end of the row, with the
    # card count parked in the middle away from the figure it belongs with. It is a cousin of the
    # `/archetypes` index bug rather than the same one: that container did not wrap, so the note
    # overflowed and grew the row; this one wraps, so nothing overflows and the damage is *worst*
    # at full width, where there is free space to spread into. Measured by adjacency at both
    # widths in ArchetypeMetagameTest, because a text assertion sees the same string either way.
    def meta
      div(class: "archetype-category-meta") do
        span(class: "archetype-category-count") do
          "#{@category.cards_count} #{'card'.pluralize(@category.cards_count)}"
        end
        # Withheld for a caller that built the group without a sample behind it — the styleguide,
        # a component test. A section this report built always knows: see CategoryGroup.
        span(class: "archetype-category-copies") { copies_text(@category) } if @category.copies_known?
      end
    end
  end
end
