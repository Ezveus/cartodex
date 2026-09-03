module Ui
  # The button that reaches the search from anywhere: it opens Search::Overlay, or — on the two
  # pages that render a Search::Spotlight inline — focuses the field already on the page. Which of
  # the two happens is the search-overlay controller's call, not this component's.
  #
  # Its own component rather than a private method on Ui::NavbarShell so the styleguide can render
  # the shipped button instead of a copy of its markup.
  class SearchTrigger < ApplicationComponent
    def view_template
      button(
        type: "button",
        class: "navbar-search-trigger",
        data: { action: "search-overlay#open" },
        aria: { label: "Search" }
      ) do
        span(class: "navbar-search-trigger-icon", aria_hidden: "true")
        span(class: "navbar-search-trigger-hint", aria_hidden: "true") { "⌘K" }
      end
    end
  end
end
