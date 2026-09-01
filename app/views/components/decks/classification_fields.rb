module Decks
  # Shared classification inputs (support, format) reused by the new-deck form
  # and the inline header edit form. The companion Stimulus controller
  # `deck-classification` toggles the conditional fields.
  #
  # There is no proxy input: whether a deck holds proxies is derived from its
  # cards' owned_copies, adjusted per card on the deck page.
  class ClassificationFields < ApplicationComponent
    def initialize(form:, deck:)
      @form = form
      @deck = deck
    end

    def view_template
      div(class: "deck-classification-fields", data: { controller: "deck-classification" }) do
        support_fieldset
        format_group
        standard_pool_field
        other_format_field
        render Decks::ArchetypeField.new(form: @form, deck: @deck)
      end
    end

    private

    def support_fieldset
      fieldset(class: "form-fieldset") do
        legend(class: "form-label") { "Support" }
        label(class: "form-check") do
          @form.check_box :physical
          plain "Physical deck"
        end
        label(class: "form-check") do
          @form.check_box :tcg_live
          plain "TCG Live deck"
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
          data: { deck_classification_target: "format", action: "deck-classification#toggle" }
      end
    end

    # Standard rotates, so a deck has to say which Standard. Conditional on the
    # format for the same reason other_format_name is: the other three formats are
    # eternal and have no pool.
    def standard_pool_field
      div(class: "form-group deck-standard-pool-field",
          data: { deck_classification_target: "standardField" },
          style: hidden_unless(@deck.standard?)) do
        label(class: "form-label", for: "deck_standard_pool_id") { "Standard" }
        @form.collection_select :standard_pool_id, pools, :id, :name,
          { selected: @deck.standard_pool_id || StandardPool.current&.id },
          class: "form-input", id: "deck_standard_pool_id"
      end
    end

    def pools
      @pools ||= StandardPool.includes(:first_card_set, :last_card_set).by_release
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
