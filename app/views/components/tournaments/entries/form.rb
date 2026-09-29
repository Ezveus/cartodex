module Tournaments
  module Entries
    class Form < ApplicationComponent
      def initialize(tournament:, entry:, decks:, tournament_profiles:, version_prompt: nil, versions: [], periods: {})
        @tournament = tournament
        @entry = entry
        @decks = decks
        @tournament_profiles = tournament_profiles
        @version_prompt = version_prompt
        # Array(): a controller that renders this form from a path which never assigned
        # @entry_versions passes nil, and the form should lose a field rather than raise.
        @versions = Array(versions)
        @periods = periods || {}
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

          version_prompt if @version_prompt

          render Ui::FormGroup.new do
            f.label :deck_id, "Deck", class: "form-label"
            f.collection_select :deck_id, @decks, :id, :name, {}, class: "form-input"
          end

          version_select(f) if @versions.any?

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

      # The server's question, not the form's: it is rendered only once a create came back
      # because the deck's list has changed since its latest version. `version_choice` is a
      # top-level param rather than an entry attribute, since it says which version to use —
      # possibly one that does not exist yet — and not a column of the entry. Required, so the
      # browser asks again instead of posting a choice-less form the server would only refuse.
      def version_prompt
        current = @version_prompt[:current]
        following = @version_prompt[:next]

        fieldset(class: "form-fieldset entry-version-prompt") do
          # The server's sentence, which says whether the cards, the format or only the pool moved.
          legend(class: "form-label") { @version_prompt[:message] }
          p(class: "form-hint") { "Which list did you play at this event?" }
          version_choice("new", "Create version #{following} from the current list")
          version_choice("current", "Attach to version #{current}")
        end
      end

      def version_choice(value, text)
        label(class: "form-check") do
          input(type: "radio", name: "version_choice", value: value, required: true)
          plain text
        end
      end

      # The versions of the deck the entry was saved with. Moving the entry moves every result
      # attached to it, which the hint says because nothing else on the page would.
      def version_select(form)
        render Ui::FormGroup.new(hint: "Its results move with it.") do
          form.label :deck_version_id, "Version", class: "form-label"
          form.select :deck_version_id,
            @versions.map { |version| [ DeckVersions::Labels.option(version, @periods[version.id]), version.id ] },
            {}, class: "form-input"
        end
      end

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
