module Ui
  # The app's one pager. Four listings render it — the card catalog, the shared decks, the
  # tournament catalog and an event's standings sheet — and until the fourth arrived each carried
  # its own copy of the same nine lines, differing only in how it built a URL.
  #
  # `href` is a callable rather than a Phlex block: it is asked for a *value* (a path) twice, not
  # for markup, and a block passed to a Phlex component is content.
  #
  # `turbo_action` is opt-in, and the reason is Back. Inside a Turbo Frame the frame swaps without
  # touching the address bar, so `data-turbo-action="replace"` is what puts `?page=` into it at
  # all — the three listings whose pagers sit in a frame pass it. On an ordinary page the link
  # already navigates and updates the URL, and `replace` would only overwrite the history entry,
  # so pressing Back from page 2 would skip page 1 entirely.
  class Pagination < ApplicationComponent
    def initialize(page:, pages:, href:, turbo_action: nil)
      @page = page
      @pages = pages
      @href = href
      @turbo_action = turbo_action
    end

    def view_template
      return unless @pages.to_i > 1

      nav(class: "cards-pagination") do
        page_link("← Previous", @page - 1) if @page > 1
        span(class: "cards-pagination-info") { "Page #{@page} / #{@pages}" }
        page_link("Next →", @page + 1) if @page < @pages
      end
    end

    private

    def page_link(label, page)
      link_to label, @href.call(page), class: "cards-pagination-link", data: link_data
    end

    def link_data
      return {} if @turbo_action.blank?

      { turbo_action: @turbo_action }
    end
  end
end
