module Tournaments
  module Standings
    # Shared by new and edit. The archetype comes from Ui::ArchetypePicker with no deck: a
    # standing names an archetype and has no line-up to suggest one from.
    class Form < ApplicationComponent
      include Phlex::Rails::Helpers::HiddenFieldTag
      include Phlex::Rails::Helpers::TextAreaTag

      # What the division select shows when nothing prefilled it. Presentation only: the enum's
      # `validate: true` still rejects a blank on the way in, this merely stops the browser
      # choosing for the user.
      DEFAULT_DIVISION = "masters"

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
            # An explicit selected:. DIVISIONS runs junior-senior-masters, and prefill_attributes
            # yields no division at all for a member with no TournamentProfile — so the browser
            # picked the first option and quietly recorded them as a Junior. Masters is the
            # default because it is the division a standings sheet overwhelmingly records, and a
            # wrong pre-selection here is a wiki edit away rather than a refusal.
            f.select :division,
              TournamentStanding::DIVISIONS.map { |d| [ d.capitalize, d ] },
              { selected: @standing.division || DEFAULT_DIVISION }, class: "form-input"
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

          render Ui::FormGroup.new(hint: decklist_hint) do
            label(class: "form-label", for: "decklist") { "Decklist (optional)" }
            text_area_tag(:decklist, nil, class: "form-input", id: "decklist", rows: 10,
              placeholder: "4 Doublade TWM 62\n…")
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

      # Reads the same division the select is showing, default included: with a bare
      # @standing.division this said "leave blank if nobody remembers" for every new row whose
      # division was not prefilled, while the select beside it already read Masters and the event
      # knew how big that field was.
      def placement_hint
        division = @standing.division || DEFAULT_DIVISION
        field = @tournament.participant_count_for(division)
        return "Optional — leave blank if nobody remembers the final standing." if field.blank?

        "The #{division} field at this event held #{field} players."
      end

      # Outside the tournament_standing hash, like tournament_entry_id: the text is not an
      # attribute of the row, it is the payload of a background import. The list it produces
      # belongs to the event and to nobody, and no UI can edit it afterwards.
      def decklist_hint
        return "Paste the list to import it. The row is saved either way." unless @standing.deck

        "This standing already has a field list. Pasting a new one imports a second."
      end
    end
  end
end
