module Search
  # /search?q=… opened as a page — what a browser's search engine lands on. It renders the
  # spotlight's own ResultsList over the same results, so the two cannot answer differently: this
  # is the panel without its frame. ResultsList rather than ResultsView because the overlay on
  # this page already holds the one element carrying ResultsView::FRAME_ID.
  class PageView < ApplicationComponent
    def initialize(results:)
      @results = results
    end

    def view_template
      content_for(:title, title)

      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Search")
        if @results.blank?
          p(class: "search-page-hint") do
            plain "Type at least #{Global::MIN_QUERY_LENGTH} characters to search decks, cards, " \
                  "tournaments and archetypes."
          end
        else
          p(class: "search-page-hint") { "Results for “#{@results.query}”" }
          div(class: "search-page-results") { render ResultsList.new(results: @results) }
        end
      end
    end

    private

    def title
      @results.query.empty? ? "Search — Cartodex" : "#{@results.query} — Cartodex search"
    end
  end
end
