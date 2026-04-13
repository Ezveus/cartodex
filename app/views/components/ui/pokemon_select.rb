# frozen_string_literal: true

module Ui
  # Renders a Pokémon autocomplete group: a visible text input, an optional hidden ID
  # field, and a results dropdown — all wrapped in a `Ui::FormGroup`.
  #
  # ## Standalone mode (own `pokemon-select` Stimulus controller)
  #
  # Pass `hidden_field_name:` to render a plain hidden input owned by the
  # `pokemon-select` controller. Use when there is no parent form builder.
  #
  #   render Ui::PokemonSelect.new(
  #     label: "Primary Pokémon",
  #     hidden_field_name: "archetype[primary_pokemon_id]",
  #     current_value: @archetype.primary_pokemon&.name
  #   )
  #
  # ## Embedded mode (parent Stimulus controller provides targets)
  #
  # Omit `hidden_field_name:`. Supply explicit `data:` hashes for each element.
  # Optionally yield a block to render a custom hidden field (e.g. from a form builder).
  #
  #   render Ui::PokemonSelect.new(
  #     label: "Primary Pokémon",
  #     hidden_data: { result_modal_target: "primaryId" },
  #     input_data:  { result_modal_target: "primaryInput",
  #                    action: "input->result-modal#searchPrimary" },
  #     results_data: { result_modal_target: "primaryResults" }
  #   )
  #
  # ## Form-builder hidden field (block form)
  #
  #   render Ui::PokemonSelect.new(
  #     label: "Primary Pokémon",
  #     current_value: pokemon&.name,
  #     input_data:  { pokemon_select_target: "input",
  #                    action: "input->pokemon-select#search" },
  #     results_data: { pokemon_select_target: "results" },
  #     wrapper_data: { controller: "pokemon-select" }
  #   ) do
  #     f.hidden_field :primary_pokemon_id, data: { pokemon_select_target: "hiddenField" }
  #   end
  class PokemonSelect < ApplicationComponent
    STANDALONE_INPUT_DATA = { pokemon_select_target: "input", action: "input->pokemon-select#search" }.freeze
    STANDALONE_RESULTS_DATA = { pokemon_select_target: "results" }.freeze
    STANDALONE_HIDDEN_DATA = { pokemon_select_target: "hiddenField" }.freeze

    # @param label             [String]       Label text shown above the input
    # @param placeholder       [String]       Placeholder for the text input
    # @param current_value     [String, nil]  Pre-filled display value
    # @param hidden_field_name [String, nil]  Activates standalone mode; name attr for hidden input
    # @param input_data        [Hash, nil]    data-* attrs for the text input (embedded/block mode)
    # @param hidden_data       [Hash, nil]    data-* attrs for the hidden input (embedded mode)
    # @param results_data      [Hash, nil]    data-* attrs for the results div (embedded/block mode)
    # @param wrapper_data      [Hash, nil]    data-* attrs for the FormGroup wrapper div
    def initialize(
      label:,
      placeholder: "Search Pokémon...",
      current_value: nil,
      hidden_field_name: nil,
      input_data: nil,
      hidden_data: nil,
      results_data: nil,
      wrapper_data: nil
    )
      @label = label
      @placeholder = placeholder
      @current_value = current_value
      @hidden_field_name = hidden_field_name
      @input_data = input_data
      @hidden_data = hidden_data
      @results_data = results_data
      @wrapper_data = wrapper_data
    end

    def view_template(&block)
      form_group_attrs = { label: @label }
      form_group_attrs[:data] = effective_wrapper_data if effective_wrapper_data.present?

      render Ui::FormGroup.new(**form_group_attrs) do
        if standalone?
          render_standalone_fields
        else
          render_embedded_fields(&block)
        end
      end
    end

    private

    def standalone?
      @hidden_field_name.present?
    end

    def effective_wrapper_data
      return @wrapper_data if @wrapper_data
      return { controller: "pokemon-select" } if standalone?

      nil
    end

    def render_standalone_fields
      input(
        type: "text",
        class: "form-input",
        placeholder: @placeholder,
        value: @current_value,
        data: @input_data || STANDALONE_INPUT_DATA
      )
      input(
        type: "hidden",
        name: @hidden_field_name,
        data: @hidden_data || STANDALONE_HIDDEN_DATA
      )
      div(class: "archetype-search-results", data: @results_data || STANDALONE_RESULTS_DATA)
    end

    def render_embedded_fields
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
