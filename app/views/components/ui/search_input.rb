# frozen_string_literal: true

module Ui
  class SearchInput < ApplicationComponent
    def initialize(
      placeholder: "Search...",
      input_class: "form-input",
      results_class: "card-search-results",
      wrapper_class: nil,
      controller: nil,
      input_target: nil,
      input_action: nil,
      results_target: nil,
      **wrapper_data
    )
      @placeholder = placeholder
      @input_class = input_class
      @results_class = results_class
      @wrapper_class = wrapper_class
      @controller = controller
      @input_target = input_target
      @input_action = input_action
      @results_target = results_target
      @wrapper_data = wrapper_data
    end

    def view_template
      wrapper_data = @wrapper_data.dup
      wrapper_data[:controller] = @controller if @controller

      div(class: @wrapper_class, data: wrapper_data.presence) do
        input(
          type: "text",
          placeholder: @placeholder,
          class: @input_class,
          data: input_data
        )
        div(class: @results_class, data: results_data)
      end
    end

    private

    def input_data
      {}.tap do |d|
        d[@input_target.to_sym] = "input" if @input_target
        d[:action] = @input_action if @input_action
      end.presence
    end

    def results_data
      { @results_target.to_sym => "results" }.presence if @results_target
    end
  end
end
