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

      # How much a line asks of the admin, which is also the order the lines are printed in.
      # *decide*: nothing is selected, and left so the deck's rows are refused by name. *check*: a
      # machine's proposal is selected and will be stored as-is on submit. *confirmed*: an answer a
      # human gave on an earlier run. Measured on event 578: 1, 2 and 25 lines of 28 — so without
      # the order the three that matter sat among the 25 that do not, in the event's own order.
      ATTENTION = { decide: 0, check: 1, confirmed: 2 }.freeze
      ATTENTION_BADGES = { decide: "badge-danger", check: "badge-warning", confirmed: "badge-success" }.freeze

      def initialize(lines:, archetypes:)
        @lines = lines
        @archetypes = archetypes
      end

      def view_template
        section(class: "standings-import-mappings") do
          h2 { "Decks in this event" }
          lead
          summary

          render Ui::DataTable.new(columns: [ "Deck", "Proposal", "Archetype" ]) do |t|
            ordered_lines.each do |line|
              attention = attention(line)
              t.row(class: "standings-import-mapping standings-import-mapping--#{attention}",
                    data: { controller: "mapping-archetype" }) do
                t.cell { deck_cell(line) }
                t.cell { proposal_cell(line, attention) }
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

      # Stable within a group: the event's own order is what the admin reads the plan below in.
      def ordered_lines
        @lines.each_with_index.sort_by { |line, index| [ ATTENTION.fetch(attention(line)), index ] }.map(&:first)
      end

      def attention(line)
        return :confirmed if line.confirmed
        return :check if line.selected_archetype

        :decide
      end

      # Counted before the table so the admin knows how many lines they are looking for. A group
      # at zero is not printed: "0 to decide" is noise on the second event, where that is normal.
      def summary
        counts = @lines.map { |line| attention(line) }.tally
        parts = {
          decide: "#{counts[:decide]} to decide",
          check: "#{counts[:check]} #{"proposal".pluralize(counts[:check].to_i)} to check",
          confirmed: "#{counts[:confirmed]} confirmed earlier"
        }.select { |attention, _| counts[attention].to_i.positive? }
        return if parts.empty?

        p(class: "standings-import-mapping-summary") do
          parts.each do |attention, text|
            span(class: "badge #{ATTENTION_BADGES.fetch(attention)}") { text }
            plain " "
          end
        end
      end

      def deck_cell(line)
        plain line.label
        plain " "
        # The key the answer is stored under, printed because two decks can read alike: 284 is
        # Dragapult and 284/3 is Dragapult Dusknoir.
        span(class: "standings-import-reference") { line.reference }
      end

      def proposal_cell(line, attention)
        badge = "badge #{ATTENTION_BADGES.fetch(attention)}"
        return span(class: badge) { line.error } if line.error.present?

        verdict = line.verdict
        span(class: badge) { VERDICT_LABELS.fetch(verdict, verdict.to_s) }
        return if line.selected_archetype.nil?

        plain " "
        plain line.selected_archetype.name
      end

      # One wrapper around everything the cell holds: below the breakpoint a cell is a flex row
      # that spreads its children apart, and the select, the button and the create section have to
      # stack as one value beside the column's label instead.
      def archetype_cell(line)
        div(class: "standings-import-mapping-choice") do
          # The label travels with the selection: limitless_archetype_mappings.label is NOT NULL,
          # #create never fetches, and nothing else on the POST could say what deck 284/3 is called.
          input(type: "hidden", name: label_field(line), value: line.label)
          div(class: "standings-import-mapping-pick") do
            select(name: archetype_field(line), class: "form-input",
                   data: { mapping_archetype_target: "select", action: "change->mapping-archetype#answered" }) do
              option(value: "") { "— Leave unmapped —" }
              @archetypes.each do |archetype|
                option(value: archetype.id.to_s, selected: archetype.id == line.selected_archetype&.id) do
                  archetype.name
                end
              end
            end
            # A text button beside the select, not a filled one beneath it: it is on all 28 lines
            # and wanted on one; stacked beneath, it grew every closed row from 73px to 112px at 1400.
            button(type: "button", class: "standings-import-mapping-new",
                   data: { action: "mapping-archetype#toggle" }) { "+ New archetype" }
          end
          create_section(line)
        end
      end

      # Offered on every line, the confirmed ones included: a proposal or an old confirmation can be
      # wrong precisely because the right archetype does not exist yet.
      #
      # **No input in here carries a `name`**, and that is what keeps it out of the confirm POST:
      # this section sits inside the form that stores every mapping and enqueues the run. The same
      # reason Enter is swallowed on the two searches — implicit submission from a search box would
      # be a click on "Confirm mappings and import".
      def create_section(line)
        primary, secondary = Array(line.proposal&.suggested_cards)

        div(class: "standings-import-mapping-create", hidden: true,
            data: { mapping_archetype_target: "createSection" }) do
          card_search("Primary card", "primaryId", primary)
          card_search("Secondary card (optional)", "secondaryId", secondary)
          div(class: "form-actions") do
            button(type: "button", class: "btn btn-primary btn-sm",
                   data: { action: "mapping-archetype#create", mapping_archetype_target: "createButton" }) do
              "Create & select"
            end
            button(type: "button", class: "btn btn-secondary btn-sm",
                   data: { action: "mapping-archetype#toggle" }) { "Cancel" }
          end
        end
      end

      # Pre-filled from the representative list by the published name — see
      # Tournaments::ArchetypeProposer#suggested_cards for why it is not the detector's suggestion.
      def card_search(label, target, card)
        render Ui::CardSelect.new(
          label: label,
          current_value: card&.printing_label,
          input_data: { card_select_target: "input",
                        action: "input->card-select#search input->mapping-archetype#forget " \
                                "keydown.enter->mapping-archetype#swallowEnter" },
          results_data: { card_select_target: "results" },
          wrapper_data: { controller: "card-select" }
        ) do
          input(type: "hidden", value: card&.id&.to_s,
                data: { card_select_target: "hiddenField", mapping_archetype_target: target })
        end
      end

      # Strings, never Symbols: Phlex dasherizes a Symbol attribute *value*, and
      # `name="mappings-284-3-archetype-id"` reaches the controller as nothing at all.
      def archetype_field(line) = "mappings[#{line.reference}][archetype_id]"
      def label_field(line) = "mappings[#{line.reference}][label]"
    end
  end
end
