module Tournaments
  module Entries
    class Form < ApplicationComponent
      def initialize(tournament:, entry:, decks:, tournament_profiles:)
        @tournament = tournament
        @entry = entry
        @decks = decks
        @tournament_profiles = tournament_profiles
      end

      def view_template
        # An explicit url: — the route resource is `entries` while the model is TournamentEntry,
        # so polymorphic form_with would build tournament_tournament_entries_path.
        form_with(model: @entry, url: form_url, class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @entry)

          # One is filling in a placement and needs to see in what. Read-only: the event's own
          # fields are edited from its fiche, by whoever catalogued it.
          p(class: "form-hint") do
            plain "#{@tournament.name} — "
            plain localize(@tournament.date, format: :long)
          end

          render Ui::FormGroup.new do
            f.label :deck_id, "Deck", class: "form-label"
            f.collection_select :deck_id, @decks, :id, :name, {}, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :tournament_profile_id, "Tournament profile (optional)", class: "form-label"
            f.collection_select :tournament_profile_id, @tournament_profiles, :id, :player_name,
              { include_blank: "— None —" }, class: "form-input"
          end

          render Ui::FormGroup.new(hint: top_cut_hint) do
            f.label :participant_count, "Number of participants", class: "form-label"
            f.number_field :participant_count, class: "form-input", min: 1
          end

          render Ui::FormGroup.new do
            f.label :placement, "Final placement", class: "form-label"
            f.number_field :placement, class: "form-input", min: 1
          end

          render Ui::FormGroup.new(hint: cp_hint) do
            f.label :championship_points, "Championship Points", class: "form-label"
            f.number_field :championship_points, class: "form-input", min: 0
          end

          div(class: "form-actions deck-form-actions") do
            f.submit class: "btn btn-primary"
            link_to "Cancel", tournament_path(@tournament), class: "btn btn-secondary"
          end
        end
      end

      private

      def form_url
        return tournament_entries_path(@tournament) unless @entry.persisted?

        tournament_entry_path(@tournament, @entry)
      end

      def top_cut_hint
        cut = @entry.standard_top_cut
        return "Standard top cut for this attendance is indicative only." if @entry.participant_count.blank?

        cut ? "Standard top cut for #{@entry.participant_count} participants: Top #{cut} (indicative)." :
          "No standard top cut for #{@entry.participant_count} participants (indicative)."
      end

      def cp_hint
        suggested = @entry.suggested_championship_points
        return "Reference CP depends on tier and placement — you can always override it." if suggested.nil?

        "Reference CP for a #{@entry.placement.ordinalize} place at this tier: #{suggested} (indicative, editable)."
      end
    end
  end
end
