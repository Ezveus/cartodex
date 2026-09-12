module Decks
  module Odds
    # How this deck opens, from the decklist alone.
    #
    # The wrapper is where the deck's own ceilings reach the controller: `d <= N - 13` and `p <= 6`
    # are properties of *this* deck, not constants a JavaScript file could hold. `turbo:frame-load`
    # is wired here rather than on the frame because the combination frame's answer ships its own
    # curve, and the scenario the reader had set has to be re-applied to it.
    class PageView < ApplicationComponent
      def initialize(deck:, report:, combo:)
        @deck = deck
        @report = report
        @combo = combo
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "#{@deck.name} — Build odds") do
            link_to "Back to Deck", deck_path(@deck), class: "btn btn-secondary"
          end

          @report.playable? ? body : render(RefusalNotice.new(report: @report))
        end
      end

      private

      def body
        div(class: "deck-odds", data: {
          controller: "deck-odds",
          action: "turbo:frame-load->deck-odds#render",
          deck_odds_max_draws_value: @report.max_draws,
          deck_odds_max_prizes_value: @report.prize_count,
          deck_odds_hand_size_value: @report.hand_size
        }) do
          render DeckSizeNotice.new(report: @report)
          render ScenarioControls.new(report: @report)
          render OpeningPanel.new(report: @report)
          render RolePanel.new(report: @report)
          render PrizePanel.new(report: @report)
          render CardTable.new(report: @report)
          # Decks::Odds::ComboCalculator is Task 8's file and outside this lane's allowlist; the
          # render of it belongs here, between the card table and the method note.
          render MethodNote.new
        end
      end
    end
  end
end
