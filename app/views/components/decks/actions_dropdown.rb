module Decks
  class ActionsDropdown < ApplicationComponent
    def initialize(deck:, edit_frame: nil, size: :sm)
      @deck = deck
      @edit_frame = edit_frame
      @size = size
    end

    def view_template
      div(class: "dropdown", data: { controller: "dropdown" }) do
        button(class: button_class, data: { action: "dropdown#toggle" }) { "Actions ▾" }
        div(class: "dropdown-menu", data: { dropdown_target: "menu" }) do
          edit_item
          duplicate_item
          delete_item
        end
      end
    end

    private

    def button_class
      [ "btn", "btn-secondary", ("btn-#{@size}" if @size) ].compact.join(" ")
    end

    def edit_item
      link_opts = { class: "dropdown-item" }
      link_opts[:data] = { turbo_frame: @edit_frame } if @edit_frame
      link_to "Edit", Rails.application.routes.url_helpers.edit_deck_path(@deck), **link_opts
    end

    def duplicate_item
      button_to "Duplicate", Rails.application.routes.url_helpers.duplicate_deck_path(@deck),
        method: :post,
        class: "dropdown-item",
        form: { class: "dropdown-item-form" }
    end

    def delete_item
      button_to "Delete", Rails.application.routes.url_helpers.deck_path(@deck),
        method: :delete,
        class: "dropdown-item dropdown-item-danger",
        form: { class: "dropdown-item-form", data: { turbo_confirm: "Delete this deck? Cards and results will be permanently removed." } }
    end
  end
end
