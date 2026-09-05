module Archetypes
  # One category of the report. The card count in the heading counts *printings*, which is
  # CategoryGroup#cards_count's own definition — three Hoothoots are three cards a player may have
  # to recognise, even though they are one name in the list below.
  class CategorySection < ApplicationComponent
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
          span(class: "archetype-category-count") do
            "#{@category.cards_count} #{'card'.pluralize(@category.cards_count)}"
          end
        end

        ul(class: "archetype-card-list") do
          @category.name_groups.each do |group|
            render Archetypes::NameGroupRow.new(group: group, single_list: @single_list)
          end
        end
      end
    end
  end
end
