module Ui
  class StatusBadge < ApplicationComponent
    VARIANTS = {
      "pending"   => "warning",
      "completed" => "success",
      "failed"    => "danger",
      "win"       => "success",
      "loss"      => "danger",
      "draw"      => nil,
      "timeout"   => "warning"
    }.freeze

    def initialize(status:, label: nil)
      @status = status
      @label = label || status
    end

    def view_template
      span(class: css_class) { @label }
    end

    private

    def css_class
      variant = VARIANTS[@status]
      variant ? "badge badge-#{variant}" : "badge"
    end
  end
end
