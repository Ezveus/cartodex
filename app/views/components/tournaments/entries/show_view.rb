module Tournaments
  module Entries
    class ShowView < ApplicationComponent
      # The event comes in rather than off the entry: EntriesController loads it through
      # Tournament.with_standard_pool (the pool and both of its card-set bounds, which
      # EventDetails prints through format_label), and entry.tournament is a fresh record that
      # throws all of it away and re-reads it lazily.
      def initialize(tournament:, entry:, unassigned_results:)
        @tournament = tournament
        @entry = entry
        @unassigned_results = unassigned_results
      end

      def view_template
        div(class: "admin-container") do
          header_section
          render Tournaments::EventDetails.new(tournament: @tournament)
          entry_section
          results_section
          unassigned_section
        end
      end

      private

      def header_section
        render Ui::PageHeader.new(title: @tournament.name) do
          div(class: "decks-header-actions") do
            link_to "Edit", edit_tournament_entry_path(@tournament, @entry), class: "btn btn-secondary"
            link_to "Tournament page", tournament_path(@tournament), class: "btn btn-secondary"
            link_to "Back to My tournaments", mine_tournaments_path, class: "btn btn-secondary"
          end
        end
      end

      def entry_section
        div(class: "tournament-details") do
          detail_row("Deck") { link_to(@entry.deck.name, deck_path(@entry.deck)) }
          detail_row("Tournament profile") { @entry.tournament_profile&.player_name || "—" }
          detail_row("Participants") { @entry.participant_count || "—" }
          detail_row("Top cut (indicative)") { top_cut_text }
          detail_row("Final placement") { placement_text }
          detail_row("Championship Points") { cp_text }
        end
      end

      def placement_text
        return "—" if @entry.placement.blank?
        return "##{@entry.placement}" if @entry.participant_count.blank?

        "##{@entry.placement} / #{@entry.participant_count}"
      end

      def top_cut_text
        cut = @entry.standard_top_cut
        return "—" if @entry.participant_count.blank?

        cut ? "Top #{cut}" : "No top cut"
      end

      def cp_text
        return @entry.championship_points.to_s if @entry.championship_points.present?

        suggested = @entry.suggested_championship_points
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

          if @entry.deck_results.any?
            render Ui::DataTable.new(columns: %w[Date Result Match Archetype Actions]) do |t|
              @entry.deck_results.order(played_at: :desc).each do |result|
                t.row do
                  t.cell { result.played_at&.strftime("%Y-%m-%d %H:%M") || "—" }
                  t.cell { render Ui::StatusBadge.new(status: result.result, label: result.result.capitalize) }
                  t.cell { result.match_format.upcase }
                  t.cell { result.archetype&.name || "—" }
                  t.cell do
                    button_to "Detach", detach_result_tournament_entry_path(@tournament, @entry, deck_result_id: result.id),
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
          form_with(url: attach_results_tournament_entry_path(@tournament, @entry), method: :post) do
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
end
