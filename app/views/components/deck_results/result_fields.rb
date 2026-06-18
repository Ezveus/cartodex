module DeckResults
  # Shared form fields for logging/editing a deck result: a BO1/BO3 format
  # toggle, the overall result buttons, and a per-game score selector for BO3.
  #
  # Renders three hidden inputs (`deck_result[match_format|result|score]`) so it
  # submits naturally inside a Rails form and can also be read by JS in the
  # result modal. All interactive behaviour is driven by the `match-result`
  # Stimulus controller, which derives the overall result from a BO3 score.
  class ResultFields < ApplicationComponent
    def initialize(result: nil)
      @result = result
    end

    def view_template
      div(class: "result-fields", data: { controller: "match-result" }) do
        input(type: "hidden", name: "deck_result[match_format]", value: match_format,
          data: { match_result_target: "matchFormatInput" })
        input(type: "hidden", name: "deck_result[result]", value: @result&.result,
          data: { match_result_target: "resultInput" })
        input(type: "hidden", name: "deck_result[score]", value: score,
          data: { match_result_target: "scoreInput" })

        format_buttons
        result_buttons
        score_section
      end
    end

    private

    def match_format
      @result&.match_format.presence || "bo1"
    end

    def score
      @result&.score.to_s
    end

    def format_buttons
      render Ui::FormGroup.new(label: "Match format") do
        div(class: "result-type-buttons match-format-buttons") do
          DeckResult::MATCH_FORMATS.each do |fmt|
            button(
              type: "button",
              class: "result-type-btn match-format-btn#{" active" if fmt == match_format}",
              data: { format: fmt, action: "match-result#selectFormat", match_result_target: "formatBtn" }
            ) { fmt.upcase }
          end
        end
      end
    end

    def result_buttons
      render Ui::FormGroup.new(label: "Result") do
        div(class: "result-type-buttons", data: { match_result_target: "resultButtons" }) do
          DeckResult::RESULTS.each do |r|
            button(
              type: "button",
              class: "result-type-btn result-#{r}#{" active" if r == @result&.result}",
              data: { result: r, action: "match-result#selectResult", match_result_target: "resultBtn" }
            ) { r.capitalize }
          end
        end
      end
    end

    def score_section
      visible = match_format == "bo3"
      games = score.chars

      div(class: "match-score-section", data: { match_result_target: "scoreSection" },
        style: ("display: none;" unless visible)) do
        p(class: "form-label") { "Score (optional)" }
        3.times { |i| game_row(i, games[i]) }
        button(type: "button", class: "btn btn-secondary btn-sm match-score-clear",
          data: { action: "match-result#clearScore" }) { "Clear score" }
      end
    end

    def game_row(index, current)
      div(class: "match-score-row", data: { match_result_target: "gameRow" }) do
        span(class: "match-score-game-label") { "Game #{index + 1}" }
        DeckResult::GAME_OUTCOMES.each do |g|
          button(
            type: "button",
            title: GAME_TITLES[g],
            class: "result-type-btn match-game-btn game-#{g.downcase}#{" active" if g == current}",
            data: { game: g, game_index: index, action: "match-result#selectGame", match_result_target: "gameBtn" }
          ) { g }
        end
      end
    end

    GAME_TITLES = { "W" => "Win", "L" => "Loss", "T" => "Timeout", "D" => "Draw" }.freeze
  end
end
