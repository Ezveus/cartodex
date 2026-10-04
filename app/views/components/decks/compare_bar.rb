module Decks
  # The floating "Compare" bar. It must sit inside the element carrying `deck-compare`, which is
  # what Decks::CompareBar.controller_data builds: the bar, the checkboxes and the deck page's
  # toggle are all that controller's targets.
  #
  # Rendered empty on purpose. The selection lives in the browser (sessionStorage), so that a deck
  # picked on /decks/shared is still picked on /decks, on page 3 of an archetype, or after a filter
  # swaps the grid — and the server never sees it until the reader presses Compare. The controller
  # fills the list in on connect.
  class CompareBar < ApplicationComponent
    # The data attributes the wrapping element needs. A class method rather than a constant
    # because the URL needs the routes, and rather than a component because the wrapper is each
    # page's own container.
    def self.controller_data(url_helpers = Rails.application.routes.url_helpers)
      { controller: "deck-compare", deck_compare_compare_url_value: url_helpers.compare_decks_path,
        deck_compare_max_value: Decks::Comparator::MAX_DECKS }
    end

    def view_template
      div(class: "deck-compare-bar", data: { deck_compare_target: "bar" }) do
        span(class: "deck-compare-bar-label") do
          span(data: { deck_compare_target: "count" }) { "0" }
          plain " selected (pick 2–#{Decks::Comparator::MAX_DECKS})"
        end
        ul(class: "deck-compare-bar-list", data: { deck_compare_target: "list" })
        div(class: "deck-compare-bar-actions") do
          button(
            type: "button", class: "btn btn-primary btn-sm", disabled: true,
            data: { deck_compare_target: "button", action: "deck-compare#compare" }
          ) { "Compare" }
          button(type: "button", class: "btn btn-secondary btn-sm", data: { action: "deck-compare#clear" }) { "Clear" }
        end
      end
    end
  end
end
