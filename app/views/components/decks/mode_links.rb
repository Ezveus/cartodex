module Decks
  # A row of mode links — "Group by: Type · Set", "View: List · Images". The current mode stays a
  # link, told apart by aria-current and a modifier: a tab that cannot be clicked reads as disabled
  # (the rule of Archetypes::CardReport's mode links).
  class ModeLinks < ApplicationComponent
    # `modes` is [[mode, label, href], …] in the order offered.
    def initialize(label:, modes:, current:)
      @label = label
      @modes = modes
      @current = current
    end

    def view_template
      div(class: "deck-group-modes") do
        span(class: "deck-group-modes-label") { @label }
        @modes.each do |mode, label, href|
          current = mode == @current
          a(href: href,
            class: [ "deck-group-mode", ("deck-group-mode--current" if current) ].compact.join(" "),
            aria_current: ("page" if current)) { label }
        end
      end
    end
  end
end
