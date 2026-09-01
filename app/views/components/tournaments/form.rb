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

        render Ui::FormGroup.new(hint: "Only used when format is “Standard”") do
          f.label :standard_pool_id, "Standard", class: "form-label"
          f.collection_select :standard_pool_id, standard_pools, :id, :name,
            { selected: selected_standard_pool_id }, class: "form-input"
          render Ui::StandardPoolNotice.new(
            record: @tournament, expected: expected_standard_pool
          )
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

    def standard_pools
      @standard_pools ||= StandardPool.named.by_release
    end

    # The pool the tournament's own date calls for, or nil when there is no date to ask
    # about. Guarded and memoized because both the pre-selection and the stale-anchor
    # notice need the same answer: unguarded, `at(nil)` returns the newest pool by
    # legal_on, and the notice would then nag about a mismatch with nothing — which is
    # exactly the state a failed update that blanked the date re-renders in.
    def expected_standard_pool
      return @expected_standard_pool if defined?(@expected_standard_pool)

      @expected_standard_pool = @tournament.date.present? ? StandardPool.at(@tournament.date) : nil
    end

    # A tournament is played under the format legal on its own date, not on "the newest pool
    # today" — a set becomes tournament-legal about two weeks after it ships, so defaulting to
    # StandardPool.current would pre-select a pool that was not yet legal when an older
    # tournament was played. Falls back to current only when there is no date to anchor on
    # (a fresh, unsaved tournament, or one re-rendered after a validation failure).
    def selected_standard_pool_id
      return @tournament.standard_pool_id if @tournament.standard_pool_id

      (expected_standard_pool || StandardPool.current)&.id
    end

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
