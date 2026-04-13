module Cards
  class AttackItem < ApplicationComponent
    def initialize(attack:)
      @attack = attack
    end

    def view_template
      div(class: "card-move") do
        div(class: "card-move-header") do
          strong { @attack.name }
          span(class: "card-move-cost") { @attack.cost } if @attack.cost.present?
          span(class: "card-move-damage") { @attack.damage } if @attack.damage.present?
        end
        p { @attack.effect } if @attack.effect.present?
      end
    end
  end
end
