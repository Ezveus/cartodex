module Decks
  # Shared classification inputs (support, format, proxies) reused by the
  # new-deck form and the inline header edit form. The companion Stimulus
  # controller `deck-classification` toggles the conditional fields.
  class ClassificationFields < ApplicationComponent
    def initialize(form:, deck:)
      @form = form
      @deck = deck
    end

    def view_template
      div(class: "deck-classification-fields", data: { controller: "deck-classification" }) do
        support_fieldset
        proxies_field
        format_group
        other_format_field
        render Decks::ArchetypeField.new(form: @form, deck: @deck)
      end
    end

    private

    def support_fieldset
      fieldset(class: "form-fieldset") do
        legend(class: "form-label") { "Support" }
        label(class: "form-check") do
          @form.check_box :physical, data: {
            deck_classification_target: "physical",
            action: "deck-classification#toggleProxies"
          }
          plain "Physical deck"
        end
        label(class: "form-check") do
          @form.check_box :tcg_live
          plain "TCG Live deck"
        end
      end
    end

    def proxies_field
      div(class: "deck-proxies-field", data: { deck_classification_target: "proxiesField" }, style: hidden_unless(@deck.physical?)) do
        label(class: "form-check") do
          @form.check_box :has_proxies
          plain "With proxies"
        end
      end
    end

    def format_group
      render Ui::FormGroup.new(label: "Format", field_name: "deck_format") do
        @form.select :format,
          Deck::FORMAT_LABELS.map { |value, label| [ label, value ] },
          {},
          class: "form-input",
          id: "deck_format",
          data: { deck_classification_target: "format", action: "deck-classification#toggleOther" }
      end
    end

    def other_format_field
      div(class: "form-group deck-other-format-field", data: { deck_classification_target: "otherField" }, style: hidden_unless(@deck.other?)) do
        label(class: "form-label", for: "deck_other_format_name") { "Format name" }
        @form.text_field :other_format_name,
          class: "form-input",
          id: "deck_other_format_name",
          placeholder: "e.g. Pocket, Theme…"
      end
    end

    def hidden_unless(condition)
      condition ? nil : "display: none"
    end
  end
end
