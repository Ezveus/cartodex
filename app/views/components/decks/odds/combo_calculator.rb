module Decks
  module Odds
    # "What are the odds I see at least one of each of these, by then?"
    #
    # Composed bucket-first: a group is a block, and cards are added to it from a list of the deck's
    # own groups that ships with the page. Ui::CardSelect is deliberately not reused — it searches the
    # whole catalogue through the API, which is the wrong population here; its shape (a field plus a
    # results list) is the idiom being followed, not the component.
    class ComboCalculator < ApplicationComponent
      def initialize(report:, combo:)
        @report = report
        @combo = combo
      end

      def view_template
        section(class: "odds-panel odds-combo", data: {
          controller: "deck-combo",
          deck_combo_url_value: odds_deck_path(@report.deck),
          deck_combo_max_buckets_value: Combo::MAX_BUCKETS
        }) do
          h2 { "Combination" }
          p(class: "odds-note") do
            plain "A group is an OR and the groups are an AND: \"one of these, and one of those\". " \
                  "Up to #{Combo::MAX_BUCKETS} groups, and a card can only be in one of them."
          end

          render ComboFrame.new(report: @report, combo: @combo)
          picker
        end
      end

      private

      # The whole list, shipped with the page and filtered in the browser: about 25 entries, so no
      # request should be needed to look at them. Hidden until a group asks for it.
      #
      # Outside the frame on purpose — it is the deck's card list, which a navigation cannot change,
      # and re-sending 25 buttons per pick would be the only thing in the response that grew with the
      # decklist. What a frame load *does* change is which of them are already used, and that is the
      # one thing the controller re-greys.
      def picker
        div(class: "odds-combo-picker", hidden: true,
            data: { deck_combo_target: "picker", action: "keydown.esc->deck-combo#closePicker" }) do
          input(type: "search", class: "form-input", placeholder: "Filter this deck's cards…",
                aria_label: "Filter this deck's cards",
                data: { deck_combo_target: "filter", action: "input->deck-combo#filter" })

          ul(class: "odds-combo-options") do
            @report.card_rows.each do |row|
              li do
                button(type: "button", class: "odds-combo-option",
                       data: { deck_combo_target: "option",
                               deck_combo_key_param: row.key,
                               action: "deck-combo#pick" }) { "#{row.name} (#{row.copies})" }
              end
            end
          end
        end
      end
    end
  end
end
