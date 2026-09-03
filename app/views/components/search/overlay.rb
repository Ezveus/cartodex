module Search
  # The spotlight in a <dialog>, for every page that does not render a field of its own. It wraps
  # the very same Search::Spotlight the dashboard shows inline: this component decides *where* the
  # field lives, never what it is, so the two surfaces cannot drift.
  #
  # Esc is handled here rather than left to the dialog's native cancel: the field binds
  # keydown.esc with preventDefault to clear the query, which kills that default. The event still
  # bubbles, so one press empties the field and closes the dialog.
  class Overlay < ApplicationComponent
    def view_template
      dialog(
        class: "search-overlay",
        aria_label: "Search",
        data: {
          search_overlay_target: "dialog",
          action: "click->search-overlay#clickBackdrop keydown.esc->search-overlay#close"
        }
      ) do
        # A modal <dialog> is its own backdrop as far as a click is concerned — clickBackdrop
        # keys on exactly that — so padding on the dialog itself would make the visible ring
        # around the field a dismiss zone. The wrapper carries it instead.
        div(class: "search-overlay-content") { render Search::Spotlight.new }
      end
    end
  end
end
