module Admin
  module StandingsImports
    # The inputs a run takes, posting nowhere: this form is a GET onto #preview, so a plan is
    # reachable by reload and by bookmark, and the browser is never asked to answer a POST with a
    # rendered body — which Turbo refuses.
    #
    # One field for the source: the Limitless URL the admin is looking at. Which of the three pages
    # it is, and the values a run is addressed by, are read off it by Tournaments::LimitlessUrl —
    # the admin used to split that address into a source select and five fields by hand.
    class Form < ApplicationComponent
      def initialize(url:, archetype_id:, event_filters:, limit_per_event:, archetypes:)
        @url = url
        @archetype_id = archetype_id
        @event_filters = event_filters
        @limit_per_event = limit_per_event
        @archetypes = archetypes
      end

      def view_template
        form_with(url: preview_admin_standings_imports_path, method: :get, class: "deck-form") do
          url_field
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

      def url_field
        render Ui::FormGroup.new(
          label: "Limitless URL", field_name: "url",
          hint: "Paste the address of the page to import. A paper deck's results " \
            "(limitlesstcg.com/decks/284/results) reads one archetype's tournament history. An online " \
            "leaderboard (play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=30C) " \
            "reads its best finishes in one card pool, de-duplicated to one row per player and list; " \
            "its set decides the Standard pool. An event (limitlesstcg.com/tournaments/578) reads every " \
            "division of one real-world tournament, whose rows carry a deck each rather than one archetype."
        ) do
          # type="url" would hand the refusal to the browser, which knows nothing of the three pages
          # and refuses nothing a copied address bar produces. The server says which page it wanted.
          input(type: "text", name: "url", id: "url", value: @url, class: "form-input",
                inputmode: "url", autocomplete: "off", spellcheck: "false",
                placeholder: "https://limitlesstcg.com/decks/284/results")
        end
      end

      # A select rather than the app's Ui::ArchetypePicker: the picker exists to let a member
      # invent an archetype while recording a deck, and nothing here may create one — the archetype
      # is the admin's declaration about a whole page of results (D2), so it is picked from what
      # cartodex already knows or the run does not happen.
      def archetype_field
        render Ui::FormGroup.new(
          label: "Archetype", field_name: "archetype_id",
          hint: "Every row a paper or online run writes carries it. Nothing is guessed and no archetype is created. Not read for a whole event, whose decks are arbitrated one by one under the preview."
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
