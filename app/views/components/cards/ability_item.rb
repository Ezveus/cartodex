module Cards
  class AbilityItem < ApplicationComponent
    def initialize(ability:)
      @ability = ability
    end

    def view_template
      div(class: "card-move") do
        strong { @ability.name }
        p { @ability.effect } if @ability.effect.present?
      end
    end
  end
end
