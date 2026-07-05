module Tournaments
  class Form < ApplicationComponent
    def initialize(tournament:, decks:, tournament_profiles:)
      @tournament = tournament
      @decks = decks
      @tournament_profiles = tournament_profiles
    end

    def view_template
      form_with(model: @tournament, class: "deck-form") do |f|
        render Ui::FormErrors.new(resource: @tournament)

        render Ui::FormGroup.new do
          f.label :name, class: "form-label"
          f.text_field :name, class: "form-input", autofocus: true, placeholder: "2026 Los Angeles Regional Championships"
        end

        render Ui::FormGroup.new do
          f.label :date, class: "form-label"
          f.date_field :date, class: "form-input"
        end

        render Ui::FormGroup.new do
          f.label :deck_id, "Deck", class: "form-label"
          f.collection_select :deck_id, @decks, :id, :name, {}, class: "form-input"
        end

        render Ui::FormGroup.new do
          f.label :tier, "Tournament tier", class: "form-label"
          f.select :tier, Tournament::TIER_LABELS.map { |value, label| [ label, value ] }, {}, class: "form-input"
        end

        render Ui::FormGroup.new do
          f.label :format, class: "form-label"
          f.select :format, Tournament::FORMAT_LABELS.map { |value, label| [ label, value ] }, {}, class: "form-input"
        end

        render Ui::FormGroup.new(hint: "Only used when format is “Other”") do
          f.label :other_format_name, "Format name", class: "form-label"
          f.text_field :other_format_name, class: "form-input", placeholder: "e.g. Pocket, Theme…"
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
          link_to "Cancel", tournaments_path, class: "btn btn-secondary"
        end
      end
    end

    private

    def top_cut_hint
      cut = @tournament.standard_top_cut
      return "Standard top cut for this attendance is indicative only." if @tournament.participant_count.blank?

      cut ? "Standard top cut for #{@tournament.participant_count} participants: Top #{cut} (indicative)." :
        "No standard top cut for #{@tournament.participant_count} participants (indicative)."
    end

    def cp_hint
      suggested = @tournament.suggested_championship_points
      return "Reference CP depends on tier and placement — you can always override it." if suggested.nil?

      "Reference CP for a #{@tournament.placement.ordinalize} place at this tier: #{suggested} (indicative, editable)."
    end
  end
end
