module Tournaments
  class IndexView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "tournament_results".freeze

    def initialize(tournaments:, query: "", page: 1, pages: 1, attended_ids: Set.new, can_create: false)
      @tournaments = tournaments
      @query = query
      @page = page
      @pages = pages
      @attended_ids = attended_ids
      @can_create = can_create
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Tournaments") do
          link_to "Add a tournament", new_tournament_path, class: "btn btn-primary" if @can_create
        end

        search_form

        # Rows and pager inside the frame, the search field outside it: a keystroke pays the
        # pager's COUNT and one page of rows, not the whole surrounding page. Everything inside
        # is frame-scoped by default, so the row links need data-turbo-frame="_top" or a click
        # swaps the table for "Content missing".
        turbo_frame_tag(FRAME_ID) do
          if @tournaments.any?
            render Ui::DataTable.new(columns: %w[Name Date Tier Format]) do |t|
              @tournaments.each { |tournament| row(t, tournament) }
            end
            pagination if @pages > 1
          else
            p { @query.present? ? "No tournaments match this search." : "No tournaments catalogued yet." }
          end
        end
      end
    end

    private

    def row(table, tournament)
      table.row do
        table.cell do
          link_to tournament.name, tournament_path(tournament), data: { turbo_frame: "_top" }
          span(class: "tournament-attended") { "You attended" } if @attended_ids.include?(tournament.id)
        end
        table.cell { localize(tournament.date, format: :long) }
        table.cell { tournament.tier_label }
        table.cell { tournament.format_label }
      end
    end

    def search_form
      form(
        action: tournaments_path,
        method: "get",
        class: "tournaments-search",
        data: { controller: "card-filter", turbo_frame: FRAME_ID, turbo_action: "replace" }
      ) do
        input(
          type: "search",
          name: "q",
          value: @query,
          placeholder: "Tournament name…",
          class: "form-input",
          autocomplete: "off",
          aria_label: "Search tournaments",
          data: { action: "input->card-filter#debounce" }
        )
      end
    end

    # Borrows the card index's pager classes, the app's only styled pager. These links sit
    # inside FRAME_ID, so Turbo navigates the frame and leaves the address bar behind;
    # turbo_action "replace" is what puts ?page= back into it.
    def pagination
      nav(class: "cards-pagination") do
        page_link("← Previous", @page - 1) if @page > 1
        span(class: "cards-pagination-info") { "Page #{@page} / #{@pages}" }
        page_link("Next →", @page + 1) if @page < @pages
      end
    end

    def page_link(label, page)
      link_to label, tournaments_path(q: @query.presence, page: page),
        class: "cards-pagination-link", data: { turbo_action: "replace" }
    end
  end
end
