module Admin
  module StandingsImports
    # Which cartodex archetype each Limitless deck is, arbitrated once per deck.
    #
    # One line per **distinct deck reference**, never one per row: the measured event is 575 rows
    # carrying 45 decks, and asking about a deck once is the difference between a screen an admin
    # can read and one nobody would. The reference is the deck's own href — 284, 284/3 — and not
    # its name, because Limitless renames a deck as a metagame settles while the variants of one
    # base id are four different decks.
    #
    # Nothing here decides anything. Measured against real lists, containment plus the published
    # name proposes right four times in five — good enough to save an admin most of the typing,
    # nowhere near good enough for a public wiki sheet that says nothing about how an archetype
    # got there. So every line carries its reason, and a line left blank is a refusal the run
    # reports rather than a guess it makes.
    class MappingTable < ApplicationComponent
      VERDICT_LABELS = {
        confirmed: "confirmed earlier",
        decided: "proposed",
        name_says_nothing: "the name says nothing",
        ambiguous: "ambiguous — two candidates tie",
        no_candidate: "no candidate"
      }.freeze

      def initialize(lines:, archetypes:)
        @lines = lines
        @archetypes = archetypes
      end

      def view_template
        section(class: "standings-import-mappings") do
          h2 { "Decks in this event" }
          lead

          render Ui::DataTable.new(columns: [ "Deck", "Proposal", "Archetype" ]) do |t|
            @lines.each do |line|
              t.row do
                t.cell { deck_cell(line) }
                t.cell { proposal_cell(line) }
                t.cell { archetype_cell(line) }
              end
            end
          end
        end
      end

      private

      def lead
        p(class: "settings-section-lead") do
          plain "#{@lines.size} distinct #{"deck".pluralize(@lines.size)}, whatever the row count below. "
          plain "A deck left unmapped is not guessed at: its rows are refused by name, and the run "
          plain "says so. What you confirm here is remembered, so the next event only asks about "
          plain "decks nobody has seen before."
        end
      end

      def deck_cell(line)
        plain line.label
        plain " "
        # The key the answer is stored under, printed because two decks can read alike: 284 is
        # Dragapult and 284/3 is Dragapult Dusknoir.
        span(class: "standings-import-reference") { line.reference }
      end

      def proposal_cell(line)
        return span(class: "badge badge-warning") { line.error } if line.error.present?

        verdict = line.verdict
        span(class: verdict == :confirmed ? "badge badge-success" : "badge") do
          VERDICT_LABELS.fetch(verdict, verdict.to_s)
        end
        return if line.selected_archetype.nil?

        plain " "
        plain line.selected_archetype.name
      end

      def archetype_cell(line)
        # The label travels with the selection: limitless_archetype_mappings.label is NOT NULL,
        # #create never fetches, and nothing else on the POST could say what deck 284/3 is called.
        input(type: "hidden", name: label_field(line), value: line.label)
        select(name: archetype_field(line), class: "form-input") do
          option(value: "") { "— Leave unmapped —" }
          @archetypes.each do |archetype|
            option(value: archetype.id.to_s, selected: archetype.id == line.selected_archetype&.id) do
              archetype.name
            end
          end
        end
      end

      # Strings, never Symbols: Phlex dasherizes a Symbol attribute *value*, and
      # `name="mappings-284-3-archetype-id"` reaches the controller as nothing at all.
      def archetype_field(line) = "mappings[#{line.reference}][archetype_id]"
      def label_field(line) = "mappings[#{line.reference}][label]"
    end
  end
end
