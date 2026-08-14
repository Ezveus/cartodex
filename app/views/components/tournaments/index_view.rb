module Tournaments
  class IndexView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "tournament_results".freeze

    def initialize(tournaments:, query: "")
      @tournaments = tournaments
      @query = query
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Tournaments") do
          link_to "New Tournament", new_tournament_path, class: "btn btn-primary"
        end

        search_form

        # Everything inside this frame is frame-scoped by default, so the row links
        # (name, Edit, Delete) need data-turbo-frame="_top" or they would swap the
        # table for a "Content missing" error instead of navigating.
        turbo_frame_tag(FRAME_ID) do
          if @tournaments.any?
            render Ui::DataTable.new(columns: %w[Name Date Tier Deck Placement CP Actions]) do |t|
              @tournaments.each do |tournament|
                t.row do
                  t.cell { link_to tournament.name, tournament_path(tournament), data: { turbo_frame: "_top" } }
                  t.cell { localize(tournament.date, format: :long) }
                  t.cell { tournament.tier_label }
                  t.cell { tournament.deck.name }
                  t.cell { placement_label(tournament) }
                  t.cell { tournament.championship_points || "—" }
                  t.cell do
                    render Ui::AdminActions.new(
                      edit_path: edit_tournament_path(tournament),
                      delete_path: tournament_path(tournament),
                      confirm_message: "Delete #{tournament.name}?",
                      frame: "_top"
                    )
                  end
                end
              end
            end
          else
            p { @query.present? ? "No tournaments match this search." : "No tournaments yet." }
          end
        end
      end
    end

    private

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

    def placement_label(tournament)
      return "—" if tournament.placement.blank?

      label = "##{tournament.placement}"
      label += " / #{tournament.participant_count}" if tournament.participant_count.present?
      label
    end
  end
end
