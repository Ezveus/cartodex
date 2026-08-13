module Search
  # The dashboard's search field: a combobox whose results land in a floating panel below it.
  #
  # The panel is a sibling of the form rather than a child, so the frame Turbo replaces on every
  # keystroke never contains the input the user is typing in.
  class Spotlight < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    def view_template
      div(class: "spotlight", data: spotlight_data) do
        search_form
        div(class: "spotlight-panel", data: { dashboard_search_target: "panel" }) do
          turbo_frame_tag(ResultsView::FRAME_ID)
        end
      end
    end

    private

    def spotlight_data
      {
        controller: "dashboard-search",
        dashboard_search_min_length_value: Global::MIN_QUERY_LENGTH,
        action: "click@document->dashboard-search#clickOutside " \
                "keydown@document->dashboard-search#shortcut"
      }
    end

    # No data-turbo-action="replace": this must not promote the frame navigation to the page URL,
    # or typing on the dashboard would rewrite the address bar to /search?q=…
    def search_form
      form(
        action: search_path,
        method: "get",
        class: "spotlight-form",
        role: "search",
        data: { turbo_frame: ResultsView::FRAME_ID, dashboard_search_target: "form" }
      ) do
        input(
          type: "search",
          name: "q",
          placeholder: "Search decks, cards, tournaments…",
          class: "form-input spotlight-input",
          autocomplete: "off",
          role: "combobox",
          aria_expanded: "false",
          aria_autocomplete: "list",
          aria_controls: ResultsView::FRAME_ID,
          aria_label: "Search decks, cards and tournaments",
          data: {
            dashboard_search_target: "input",
            action: "input->dashboard-search#search " \
                    "keydown.down->dashboard-search#next " \
                    "keydown.up->dashboard-search#previous " \
                    "keydown.enter->dashboard-search#open " \
                    "keydown.esc->dashboard-search#close"
          }
        )
      end
    end
  end
end
