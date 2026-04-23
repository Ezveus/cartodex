module DeckResults
  class EditView < ApplicationComponent
    def initialize(deck:, result:)
      @deck = deck
      @result = result
    end

    def view_template
      div(class: "admin-container") do
        h1 { "Edit Result" }

        form_with(model: @result, url: deck_deck_result_path(@deck, @result), method: :patch, class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @result)

          render Ui::FormGroup.new do
            f.label :result, class: "form-label"
            f.select :result, DeckResult::RESULTS.map { |r| [ r.capitalize, r ] }, {}, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :archetype_id, "Archetype", class: "form-label"
            f.collection_select :archetype_id, Archetype.order(:name), :id, :name,
              { include_blank: "\u2014 None \u2014" }, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :played_at, class: "form-label"
            f.datetime_local_field :played_at, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :notes, class: "form-label"
            f.text_area :notes, class: "form-input", rows: 3
          end

          div(class: "form-actions deck-form-actions") do
            f.submit "Update Result", class: "btn btn-primary"
            link_to "Cancel", deck_deck_results_path(@deck), class: "btn btn-secondary"
          end
        end
      end
    end
  end
end
