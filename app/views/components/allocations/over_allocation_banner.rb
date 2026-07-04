module Allocations
  # A discreet alert shown at the top of /decks and /collections when the user
  # has over-allocated cards, linking to the over-allocations page. Renders
  # nothing when count is zero.
  class OverAllocationBanner < ApplicationComponent
    def initialize(count:)
      @count = count
    end

    def view_template
      return if @count.zero?

      div(class: "over-allocation-banner badge-warning") do
        plain "⚠ #{@count} #{@count == 1 ? "over-allocated card" : "over-allocated cards"} — "
        link_to "view", over_allocations_path
      end
    end
  end
end
