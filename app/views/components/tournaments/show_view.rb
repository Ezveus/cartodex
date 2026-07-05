module Tournaments
  class ShowView < ApplicationComponent
    def initialize(tournament:, unassigned_results:)
      @tournament = tournament
      @unassigned_results = unassigned_results
    end

    def view_template
      div(class: "admin-container") do
        header_section
        details_section
        results_section
        unassigned_section
      end
    end

    private

    def header_section
      render Ui::PageHeader.new(title: @tournament.name) do
        div(class: "decks-header-actions") do
          link_to "Edit", edit_tournament_path(@tournament), class: "btn btn-secondary"
          link_to "Back to Tournaments", tournaments_path, class: "btn btn-secondary"
        end
      end
    end

    def details_section
      div(class: "tournament-details") do
        detail_row("Date") { localize(@tournament.date, format: :long) }
        detail_row("Deck") { link_to(@tournament.deck.name, deck_path(@tournament.deck)) }
        detail_row("Tier") { @tournament.tier_label }
        detail_row("Format") { @tournament.format_label }
        detail_row("Tournament profile") { @tournament.tournament_profile&.player_name || "—" }
        detail_row("Participants") { @tournament.participant_count || "—" }
        detail_row("Top cut (indicative)") { top_cut_text }
        detail_row("Final placement") { @tournament.placement ? "##{@tournament.placement}" : "—" }
        detail_row("Championship Points") { cp_text }
      end
    end

    def top_cut_text
      cut = @tournament.standard_top_cut
      return "—" if @tournament.participant_count.blank?

      cut ? "Top #{cut}" : "No top cut"
    end

    def cp_text
      return @tournament.championship_points.to_s if @tournament.championship_points.present?

      suggested = @tournament.suggested_championship_points
      suggested ? "— (reference: #{suggested})" : "—"
    end

    def detail_row(label, &block)
      div(class: "data-table-row") do
        div(class: "data-table-cell") { label }
        div(class: "data-table-cell", &block)
      end
    end

    def results_section
      div(class: "tournament-results") do
        h2 { "Results" }

        if @tournament.deck_results.any?
          render Ui::DataTable.new(columns: %w[Date Result Match Archetype Actions]) do |t|
            @tournament.deck_results.order(played_at: :desc).each do |result|
              t.row do
                t.cell { result.played_at&.strftime("%Y-%m-%d %H:%M") || "—" }
                t.cell { render Ui::StatusBadge.new(status: result.result, label: result.result.capitalize) }
                t.cell { result.match_format.upcase }
                t.cell { result.archetype&.name || "—" }
                t.cell do
                  button_to "Detach", detach_tournament_deck_result_path(@tournament, result),
                    method: :delete, class: "btn btn-secondary btn-sm",
                    form: { data: { turbo_confirm: "Detach this result from the tournament?" } }
                end
              end
            end
          end
        else
          p { "No results linked yet." }
        end
      end
    end

    def unassigned_section
      return if @unassigned_results.empty?

      div(class: "tournament-unassigned-results") do
        h2 { "Attach existing results from this deck" }
        form_with(url: attach_tournament_deck_results_path(@tournament), method: :post) do
          @unassigned_results.each do |result|
            label(class: "form-check") do
              input(type: "checkbox", name: "deck_result_ids[]", value: result.id)
              plain "#{result.played_at&.strftime('%Y-%m-%d')} — #{result.result.capitalize}" \
                "#{result.archetype ? " vs #{result.archetype.name}" : ''}"
            end
          end
          div(class: "form-actions") do
            button(type: "submit", class: "btn btn-primary btn-sm") { "Attach selected" }
          end
        end
      end
    end
  end
end
