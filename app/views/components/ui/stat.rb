module Ui
  class Stat < ApplicationComponent
    VARIANTS = {
      default: { wrapper: "stat", value: "stat-value", label: "stat-label", inline: true },
      admin: { wrapper: "admin-stat-card", value: "admin-stat-value", label: "admin-stat-label", inline: false }
    }.freeze

    def initialize(value:, label:, variant: :default, value_data: nil)
      @value = value
      @label = label
      @classes = VARIANTS.fetch(variant)
      @value_data = value_data
    end

    def view_template
      div(class: @classes[:wrapper]) do
        if @classes[:inline]
          span(class: @classes[:value], data: @value_data) { @value.to_s }
          span(class: @classes[:label]) { @label }
        else
          div(class: @classes[:value], data: @value_data) { @value.to_s }
          div(class: @classes[:label]) { @label }
        end
      end
    end
  end
end
