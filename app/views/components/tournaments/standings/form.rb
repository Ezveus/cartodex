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

      # The fourth value of TournamentStanding::DIVISIONS, the one AGE_DIVISIONS does not carry.
      # Spelled out rather than derived as DIVISIONS - AGE_DIVISIONS, which would silently offer
      # any future fifth value on an online event whether or not it meant anything there.
      ONLINE_DIVISION = "open"

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
            # Both halves — which options and which one is pre-selected — are asked of the event,
            # never fixed: see #offered_divisions and #default_division below.
            #
            # An explicit selected:. AGE_DIVISIONS runs junior-senior-masters, and
            # prefill_attributes yields no division at all for a member with no TournamentProfile
            # — so the browser picked the first option and quietly recorded them as a Junior.
            # Masters is the default on a paper event because it is the division a standings sheet
            # overwhelmingly records, and a wrong pre-selection here is a wiki edit away rather
            # than a refusal.
            f.select :division, division_options,
              { selected: @standing.division || default_division }, class: "form-input"
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
            link_to "Cancel", cancel_path, class: "btn btn-secondary"
          end
        end
      end

      private

      # What the event has, plus the row's own value when it is not one of them, and the second
      # half is not a nicety. This form is shared by new *and* edit, standings are wiki-governed,
      # and standing_params permits :division — so on an imported online row a select missing
      # "open" renders no option matching it, the browser pre-selects the first, and the division
      # travels back to the server on every save whether or not anybody touched it. A member
      # opening the row to fix a typo in a player name silently refiles the result.
      def division_options
        divisions = offered_divisions
        own = @standing.division
        divisions += [ own ] if own.present? && divisions.exclude?(own)
        divisions.map { |d| [ d.capitalize, d ] }
      end

      # The list is a property of the event, because the two are mutually exclusive: a paper event
      # has three age divisions and no "open", an online one has "open" and no age divisions at
      # all. §4 fixed the edit case by keeping the row's own value in the list; this is the same
      # lie arriving through the *new* case, which that fix does not reach — a new standing takes
      # its division from the reader's TournamentProfile or from DEFAULT_DIVISION, so on an
      # imported online sheet the select offered junior/senior/masters and nothing else, and
      # Archetypes::Performance#by_division then reports an online result as a Masters one.
      #
      # Offered rather than withheld — the alternative was to drop "Add a standing" on an online
      # event, the way the participation invitations are dropped — because the two withholdings
      # answer different questions. A participation is an age-division Play! Pokémon record that
      # means nothing online, and accepting one makes the event permanently undeletable
      # (`has_many :entries, dependent: :restrict_with_error`). A standing is wiki-governed public
      # data with `dependent: :destroy` behind it, an imported online sheet is a de-duplicated
      # top-20 and therefore partial by construction, and every row already carries Edit and
      # Delete — a sheet a member may correct and delete rows from but never add one back to is
      # the odd rule, not this.
      def offered_divisions
        return [ ONLINE_DIVISION ] if @tournament.online?

        TournamentStanding::AGE_DIVISIONS
      end

      # DEFAULT_DIVISION is presentation only, so the online default costs nothing but honesty:
      # "open" is the only option an online event offers, and pre-selecting it is what stops the
      # browser choosing on the member's behalf — the same reason the explicit selected: exists.
      def default_division
        return ONLINE_DIVISION if @tournament.online?

        DEFAULT_DIVISION
      end

      def form_url
        return tournament_standings_path(@tournament) unless @standing.persisted?

        tournament_standing_path(@tournament, @standing)
      end

      # Back to the row being edited, not to the top of page one: saving returns the member there,
      # and cancelling should not cost them their place. A new row has no place yet.
      def cancel_path
        return tournament_path(@tournament) unless @standing.persisted?

        tournament_path(@tournament, **Row.sheet_position(@standing))
      end

      # Being blocked is useless without being told where to go — the other half of the
      # anti-duplicate mechanism, exactly as Tournaments::Form does it for a duplicate event. The
      # link goes to the clashing row itself, where its "This is me" button already is.
      def clash_hint
        return if @existing.nil?

        p(class: "form-hint") do
          plain "#{@existing.player_name} already has a standing in this division: "
          # sheet_position and not a bare tournament_path: the whole point is to put that row in
          # front of the member, and page one is where a sheet with a pager is least likely to
          # hold it.
          link_to "see the event's sheet", tournament_path(@tournament, **Row.sheet_position(@existing))
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
        division = @standing.division || default_division
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
