# frozen_string_literal: true

module Ui
  # Renders a card autocomplete group: a visible text input, an optional hidden ID
  # field, and a results dropdown — all wrapped in a `Ui::FormGroup`.
  #
  # Searches every card type. Its only users are the archetype pickers, and an
  # archetype may designate a Pokémon, a Trainer or an Energy.
  #
  # The component renders the fields and nothing else: a parent Stimulus
  # controller owns the targets and drives the search, which is why every `data:`
  # hash is supplied by the caller rather than defaulted here. Three callers, two
  # shapes.
  #
  # ## Parent controller provides the targets
  #
  #   render Ui::CardSelect.new(
  #     label: "Primary card",
  #     hidden_data: { result_modal_target: "primaryId" },
  #     input_data:  { result_modal_target: "primaryInput",
  #                    action: "input->result-modal#searchPrimary" },
  #     results_data: { result_modal_target: "primaryResults" }
  #   )
  #
  # ## Form-builder hidden field (block form)
  #
  # The block renders the hidden field, so a form builder can name it. Here the
  # component's own `card-select` controller does the driving, and the caller
  # wires it up through `wrapper_data:`.
  #
  #   render Ui::CardSelect.new(
  #     label: "Primary card",
  #     current_value: card&.name,
  #     input_data:  { card_select_target: "input",
  #                    action: "input->card-select#search" },
  #     results_data: { card_select_target: "results" },
  #     wrapper_data: { controller: "card-select" }
  #   ) do
  #     f.hidden_field :primary_card_id, data: { card_select_target: "hiddenField" }
  #   end
  class CardSelect < ApplicationComponent
    # @param label         [String]       Label text shown above the input
    # @param placeholder   [String]       Placeholder for the text input
    # @param current_value [String, nil]  Pre-filled display value
    # @param input_data    [Hash, nil]    data-* attrs for the text input
    # @param hidden_data   [Hash, nil]    data-* attrs for the hidden input; omit when a block renders it
    # @param results_data  [Hash, nil]    data-* attrs for the results div
    # @param wrapper_data  [Hash, nil]    data-* attrs for the FormGroup wrapper div
    def initialize(
      label:,
      placeholder: "Search cards...",
      current_value: nil,
      input_data: nil,
      hidden_data: nil,
      results_data: nil,
      wrapper_data: nil
    )
      @label = label
      @placeholder = placeholder
      @current_value = current_value
      @input_data = input_data
      @hidden_data = hidden_data
      @results_data = results_data
      @wrapper_data = wrapper_data
    end

    def view_template(&block)
      form_group_attrs = { label: @label }
      form_group_attrs[:data] = @wrapper_data if @wrapper_data.present?

      render Ui::FormGroup.new(**form_group_attrs) do
        render_fields(&block)
      end
    end

    private

    def render_fields
      input(type: "hidden", data: @hidden_data) if @hidden_data
      input(
        type: "text",
        class: "form-input",
        placeholder: @placeholder,
        value: @current_value,
        data: @input_data
      )
      yield if block_given?
      div(class: "archetype-search-results", data: @results_data)
    end
  end
end
