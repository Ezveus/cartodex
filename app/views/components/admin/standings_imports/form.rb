module Admin
  module StandingsImports
    # The inputs a run takes, posting nowhere: this form is a GET onto #preview, so a plan is
    # reachable by reload and by bookmark, and the browser is never asked to answer a POST with a
    # rendered body — which Turbo refuses.
    #
    # Both sources' fields are rendered at once and labelled with the source they belong to, rather
    # than shown and hidden by a Stimulus controller: the field the run does not read is ignored,
    # while a field JavaScript has hidden is a field an admin cannot correct when JavaScript has
    # not loaded — on the one screen in the app that writes to a public catalog.
    class Form < ApplicationComponent
      SOURCES = [
        [ "paper", "Paper events — limitlesstcg.com/decks/<id>/results" ],
        [ "online", "Online best finishes — play.limitlesstcg.com/decks/<slug>" ]
      ].freeze

      def initialize(source:, deck_id:, slug:, rotation:, set:, archetype_id:, event_filters:,
                     limit_per_event:, archetypes:)
        @source = source
        @deck_id = deck_id
        @slug = slug
        @rotation = rotation
        @set = set
        @archetype_id = archetype_id
        @event_filters = event_filters
        @limit_per_event = limit_per_event
        @archetypes = archetypes
      end

      def view_template
        form_with(url: preview_admin_standings_imports_path, method: :get, class: "deck-form") do
          source_field
          deck_id_field
          slug_field
          rotation_field
          set_field
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

      def source_field
        render Ui::FormGroup.new(
          label: "Source", field_name: "source",
          hint: "Paper reads one archetype's tournament history. Online reads its best finishes in one card pool — a top-20 leaderboard, de-duplicated to one row per player and list."
        ) do
          select(name: "source", id: "source", class: "form-input") do
            SOURCES.each do |value, label|
              option(value: value, selected: value == @source) { label }
            end
          end
        end
      end

      def deck_id_field
        render Ui::FormGroup.new(
          label: "Limitless deck id (paper)", field_name: "deck_id",
          hint: "The number in limitlesstcg.com/decks/280/results. Digits only — it goes straight into the URL this fetches."
        ) do
          # Strings, not Symbols, for every name and id: Phlex dasherizes a Symbol passed as an
          # attribute value, and `name="deck-id"` reaches the controller as nothing at all.
          input(type: "text", name: "deck_id", id: "deck_id", value: @deck_id,
                class: "form-input", inputmode: "numeric", placeholder: "280")
        end
      end

      def slug_field
        render Ui::FormGroup.new(
          label: "Leaderboard slug (online)", field_name: "slug",
          hint: "The slug in play.limitlesstcg.com/decks/raging-bolt-ogerpon. Lowercase letters, digits and dashes — it goes straight into the URL this fetches."
        ) do
          input(type: "text", name: "slug", id: "slug", value: @slug,
                class: "form-input", placeholder: "raging-bolt-ogerpon")
        end
      end

      def rotation_field
        render Ui::FormGroup.new(
          label: "Rotation (online)", field_name: "rotation",
          hint: "The four-digit year in the leaderboard's URL. A rotation and set pair that does not exist answers with an empty page, not an error, so it is refused rather than read as “no finishes”."
        ) do
          input(type: "text", name: "rotation", id: "rotation", value: @rotation,
                class: "form-input", inputmode: "numeric", placeholder: "2026")
        end
      end

      # The one input on this screen that decides something no later edit can catch: it is the
      # anchor of every row the run writes, and it is deliberately not the event's date — online
      # play follows a set's release, which runs about two weeks ahead of the date Play! Pokémon
      # considers that pool legal.
      def set_field
        render Ui::FormGroup.new(
          label: "Set (online)", field_name: "set",
          hint: "The newest set of the pool the leaderboard covers, e.g. PBL. It has to name exactly one Standard pool — that pool anchors every row this writes."
        ) do
          input(type: "text", name: "set", id: "set", value: @set,
                class: "form-input", placeholder: "PBL")
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
