module Ui
  # A filter-bar <select> that submits its form on change, shared by the two deck listings
  # (Decks::IndexView and Decks::SharedIndexView, where it was byte-identical). Both sit inside
  # a `card-filter` form, which is what `change->card-filter#submit` talks to.
  #
  # Cards::IndexView deliberately keeps its own: it styles its selects with
  # `.cards-search-select` rather than `.deck-filter-select`, and passes its "all" label
  # separately. That is a third variant, not a third copy, and folding it in here would change
  # how the card page looks.
  class FilterSelect < ApplicationComponent
    def initialize(name:, options:, selected: nil)
      @name = name
      @options = options
      @selected = selected.to_s
    end

    def view_template
      select(name: @name, class: "form-input deck-filter-select", data: { action: "change->card-filter#submit" }) do
        @options.each do |label, value|
          if value.to_s == @selected
            option(value: value, selected: true) { label }
          else
            option(value: value) { label }
          end
        end
      end
    end
  end
end
