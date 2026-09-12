module Decks
  module Odds
    # What the deck can *do*, by the roles its cards carry.
    #
    # Two sentences below the table, and both exist because the numbers alone mislead. A card is
    # filed under every role it plays, so the sections overlap and do not add up to a list — the same
    # warning Archetypes::CardReport carries, for the same reason. And role curation covers about 94
    # fingerprints of the catalogue rather than all of it, so a `search` count of 4 in a deck playing
    # twelve uncurated searchers is a lie by omission: the coverage line is printed whether or not
    # the deck happens to carry a role, since "no roles here" and "nobody has curated these yet" read
    # identically otherwise.
    class RolePanel < ApplicationComponent
      include Formatting

      COLUMNS = [ "Role", "Cards", "In opening hand", "Seen" ].freeze

      def initialize(report:)
        @report = report
      end

      def view_template
        section(class: "odds-panel") do
          h2 { "By role" }

          if @report.role_rows.any?
            table
            p(class: "odds-overlap-note") do
              plain "A card is listed under every role it plays, so a card with two roles appears " \
                    "twice and these rows add up to more than the deck."
            end
          end

          p(class: "odds-coverage-note") { coverage }
        end
      end

      private

      def table
        render Ui::DataTable.new(columns: COLUMNS) do |t|
          @report.role_rows.each do |row|
            t.row do
              t.cell { row.name }
              t.cell { row.copies.to_s }
              t.cell { percent(row.opening) }
              t.cell { render Cell.new(curve: row.accessible_curve, index: @report.default_seen) }
            end
          end
        end
      end

      # Not possessive, for the reason Decks::Odds::DeckSizeNotice is not: page_view_test.rb
      # asserts on this sentence and Phlex escapes an apostrophe to &#39;.
      def coverage
        "#{@report.uncurated_copies} of the #{@report.deck_size} cards in this deck carry no role " \
          "label yet, so a row here counts what has been curated and not what the deck plays."
      end
    end
  end
end
