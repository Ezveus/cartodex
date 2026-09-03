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
        # data-search-surface says "a click here is a click *inside* the search": the spotlight
        # watches the document for outside clicks, and this button's own click reaches that
        # watcher after it has opened the search.
        data: { action: "search-overlay#open", search_surface: true },
        aria: { label: "Search" }
      ) do
        span(class: "navbar-search-trigger-icon", aria_hidden: "true")
        # ⌘K is the default rather than the truth: the shortcut takes Ctrl+K just as well, and
        # which of the two this keyboard has is only knowable client-side, so the controller
        # rewrites this on connect.
        span(
          class: "navbar-search-trigger-hint",
          data: { search_overlay_target: "hint" },
          aria_hidden: "true"
        ) { "⌘K" }
      end
    end
  end
end
