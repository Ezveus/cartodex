module Tournaments
  module Standings
    # Shared by new and edit. The archetype comes from Ui::ArchetypePicker with no deck: a
    # standing names an archetype and has no line-up to suggest one from.
    class Form < ApplicationComponent
      include Phlex::Rails::Helpers::HiddenFieldTag

      def initialize(tournament:, standing:, existing: nil, entry: nil)
        @tournament = tournament
        @standing = standing
        @existing = existing
        @entry = entry
      end

      def view_template
        # An explicit url: — the route resource is `standings` while the model is
        # TournamentStanding, so polymorphic form_with would build
        # tournament_tournament_standings_path.
        form_with(model: @standing, url: form_url, class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @standing)
          clash_hint
          event_hint
          # Outside the tournament_standing hash on purpose: the link is not mass-assignable, and
          # the controller resolves this id through the reader's own participations.
          hidden_field_tag(:tournament_entry_id, @entry.id) if @entry

          render Ui::FormGroup.new do
            f.label :player_name, "Player name", class: "form-label"
            f.text_field :player_name, class: "form-input", autofocus: true,
              placeholder: "As it appears on the standings sheet"
          end

          render Ui::FormGroup.new do
            f.label :division, class: "form-label"
            f.select :division,
              TournamentStanding::DIVISIONS.map { |d| [ d.capitalize, d ] }, {}, class: "form-input"
          end

          render Ui::ArchetypePicker.new(form: f, selected: @standing.archetype)

          render Ui::FormGroup.new(hint: placement_hint) do
            f.label :placement, "Final placement", class: "form-label"
            f.number_field :placement, class: "form-input", min: 1
          end

          div(class: "form-row") do
            %i[wins losses ties].each do |field|
              render Ui::FormGroup.new do
                f.label field, class: "form-label"
                f.number_field field, class: "form-input", min: 0
              end
            end
          end

          div(class: "form-actions deck-form-actions") do
            f.submit class: "btn btn-primary"
            link_to "Cancel", tournament_path(@tournament), class: "btn btn-secondary"
          end
        end
      end

      private

      def form_url
        return tournament_standings_path(@tournament) unless @standing.persisted?

        tournament_standing_path(@tournament, @standing)
      end

      # Being blocked is useless without being told where to go — the other half of the
      # anti-duplicate mechanism, exactly as Tournaments::Form does it for a duplicate event. The
      # link goes to the event, where the row and its "This is me" button already are.
      def clash_hint
        return if @existing.nil?

        p(class: "form-hint") do
          plain "#{@existing.player_name} already has a standing in this division: "
          link_to "see the event's sheet", tournament_path(@tournament)
        end
      end

      # One is filling in a placement and needs to see in what. Read-only: the event's own fields
      # are edited from its fiche.
      def event_hint
        p(class: "form-hint") do
          plain "#{@tournament.name} — "
          plain localize(@tournament.date, format: :long)
        end
      end

      def placement_hint
        field = @tournament.participant_count_for(@standing.division)
        return "Optional — leave blank if nobody remembers the final standing." if field.blank?

        "The #{@standing.division} field at this event held #{field} players."
      end
    end
  end
end
