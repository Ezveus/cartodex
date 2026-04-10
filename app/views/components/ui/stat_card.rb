module Ui
  class StatCard < ApplicationComponent
    def initialize(value:, label:, css_class: "admin-stat-card")
      @value = value
      @label = label
      @css_class = css_class
    end

    def view_template
      div(class: @css_class) do
        div(class: "#{@css_class.split.first}-stat-value") { @value.to_s }
        div(class: "#{@css_class.split.first}-stat-label") { @label }
      end
    end
  end
end
