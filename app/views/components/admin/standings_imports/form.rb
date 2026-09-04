module Admin
  module StandingsImports
    # The four inputs a run takes, posting nowhere: this form is a GET onto #preview, so a plan is
    # reachable by reload and by bookmark, and the browser is never asked to answer a POST with a
    # rendered body — which Turbo refuses.
    class Form < ApplicationComponent
      def initialize(deck_id:, archetype_id:, event_filters:, limit_per_event:, archetypes:)
        @deck_id = deck_id
        @archetype_id = archetype_id
        @event_filters = event_filters
        @limit_per_event = limit_per_event
        @archetypes = archetypes
      end

      def view_template
        form_with(url: preview_admin_standings_imports_path, method: :get, class: "deck-form") do
          deck_id_field
          archetype_field
          event_filters_field
          limit_field

          div(class: "form-actions deck-form-actions") do
            # A bare <button>, not submit_tag: a GET form carries its fields in the query string,
            # and submit_tag would put `commit=Preview` in there beside them for nothing.
            button(type: "submit", class: "btn btn-primary") { "Preview" }
          end
        end
      end

      private

      def deck_id_field
        render Ui::FormGroup.new(
          label: "Limitless deck id", field_name: "deck_id",
          hint: "The number in limitlesstcg.com/decks/280/results. Digits only — it goes straight into the URL this fetches."
        ) do
          # Strings, not Symbols, for every name and id: Phlex dasherizes a Symbol passed as an
          # attribute value, and `name="deck-id"` reaches the controller as nothing at all.
          input(type: "text", name: "deck_id", id: "deck_id", value: @deck_id,
                class: "form-input", inputmode: "numeric", placeholder: "280")
        end
      end

      # A select rather than the app's Ui::ArchetypePicker: the picker exists to let a member
      # invent an archetype while recording a deck, and nothing here may create one — the archetype
      # is the admin's declaration about a whole page of results (D2), so it is picked from what
      # cartodex already knows or the run does not happen.
      def archetype_field
        render Ui::FormGroup.new(
          label: "Archetype", field_name: "archetype_id",
          hint: "Every row this run writes carries it. Nothing is guessed and no archetype is created."
        ) do
          select(name: "archetype_id", id: "archetype_id", class: "form-input") do
            option(value: "") { "— Pick an archetype —" }
            @archetypes.each do |archetype|
              option(value: archetype.id.to_s, selected: archetype.id == @archetype_id) { archetype.name }
            end
          end
        end
      end

      def event_filters_field
        render Ui::FormGroup.new(
          label: "Only these events (optional)", field_name: "event_filters",
          hint: "One per line or comma-separated. A row is kept when its event name contains any of them. Leave blank for every event on the page — which is thousands of rows."
        ) do
          textarea(name: "event_filters", id: "event_filters", class: "form-input", rows: 4,
                   placeholder: "NAIC\nWorld Championships") { @event_filters }
        end
      end

      def limit_field
        render Ui::FormGroup.new(
          label: "Top N per event (optional)", field_name: "limit_per_event",
          hint: "Applied per age division, not per event: a cap across the whole event would keep ten Masters rows and drop the single Junior one."
        ) do
          input(type: "number", name: "limit_per_event", id: "limit_per_event",
                value: @limit_per_event, class: "form-input", min: "1")
        end
      end
    end
  end
end
