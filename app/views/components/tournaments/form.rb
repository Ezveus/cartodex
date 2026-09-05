module Tournaments
  class Form < ApplicationComponent
    def initialize(tournament:, existing: nil)
      @tournament = tournament
      @existing = existing
    end

    def view_template
      form_with(model: @tournament, class: "deck-form", data: {
        controller: "tournament-standard-pool",
        tournament_standard_pool_pools_value: pool_calendar_json,
        tournament_standard_pool_fallback_id_value: StandardPool.current&.id.to_i
      }) do |f|
        render Ui::FormErrors.new(resource: @tournament)

        # Being blocked is useless without being told where to go: this is the other half of
        # the anti-duplicate mechanism, the catalog's own search being the first.
        if @existing
          p(class: "form-hint") do
            plain "This tournament is already catalogued: "
            link_to @existing.name, tournament_path(@existing)
          end
        end

        render Ui::FormGroup.new do
          f.label :name, class: "form-label"
          f.text_field :name, class: "form-input", autofocus: true, placeholder: "2026 Los Angeles Regional Championships"
        end

        render Ui::FormGroup.new do
          f.label :date, class: "form-label"
          f.date_field :date, class: "form-input",
            data: {
              tournament_standard_pool_target: "date",
              # `input` as well as `change`: a date input does not fire change until it loses
              # focus, so change alone leaves the select stale for as long as the user stays in
              # the field — and invisible to a test that never blurs it.
              action: "input->tournament-standard-pool#syncFromDate change->tournament-standard-pool#syncFromDate"
            }
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
            { selected: selected_standard_pool_id },
            class: "form-input",
            data: {
              tournament_standard_pool_target: "pool",
              action: "change->tournament-standard-pool#markOverridden"
            }
          render Ui::StandardPoolNotice.new(
            record: @tournament, expected: expected_standard_pool
          )
        end

        render Ui::FormGroup.new(hint: "Only used when format is “Other”") do
          f.label :other_format_name, "Format name", class: "form-label"
          f.text_field :other_format_name, class: "form-input", placeholder: "e.g. Pocket, Theme…"
        end

        # A standing's placement is capped against its own division's field, per
        # Tournament#participant_count_for — never against the event's total attendance, which
        # is what TournamentEntry#participant_count already records per participation. Grouped
        # under one label and hint so a user reads all four as one question, "how many players
        # in this division", rather than four unrelated counters.
        #
        # "Open" is the fourth and is not an age division — it is the field of an online event,
        # which has none. It gets an input here for the same reason the other three do, and more
        # urgently: it is the only one anything ever writes on its own (the online import), and a
        # wrong value caps every standing above it out of the wiki edit form with no other way
        # anywhere in the app to correct the number.
        render Ui::FormGroup.new(
          label: "Field size per division",
          hint: "How many players competed in each division at this event — not the event's " \
            "total attendance. “Open” is the single field of an online event, which has no age " \
            "divisions. Leave a division blank if nobody remembers. Caps a standing's " \
            "placement in that division."
        ) do
          div(class: "form-row") do
            render Ui::FormGroup.new do
              f.label :junior_participant_count, "Junior", class: "form-label"
              f.number_field :junior_participant_count, class: "form-input", min: 1
            end
            render Ui::FormGroup.new do
              f.label :senior_participant_count, "Senior", class: "form-label"
              f.number_field :senior_participant_count, class: "form-input", min: 1
            end
            render Ui::FormGroup.new do
              f.label :masters_participant_count, "Masters", class: "form-label"
              f.number_field :masters_participant_count, class: "form-input", min: 1
            end
            render Ui::FormGroup.new do
              f.label :open_participant_count, "Open (online)", class: "form-label"
              f.number_field :open_participant_count, class: "form-input", min: 1
            end
          end
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

    # Every pool's legality date, for the Stimulus controller that keeps the select in step
    # with the date field. Only `legal_on` travels: the client mirrors StandardPool.at, which
    # is the only question the date can answer, and shipping `released_on` too would invite a
    # second, wrong rule client-side.
    def pool_calendar_json
      standard_pools.map { |pool| { id: pool.id, legal_on: pool.legal_on.iso8601 } }.to_json
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
  end
end
