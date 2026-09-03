module Decks
  class ActionsDropdown < ApplicationComponent
    # `share` is false by default: this dropdown is also rendered on the decks index rows
    # (Decks::DeckCard), where no share-modal controller exists on the page, so a
    # share-modal#open button there would do nothing. Only the deck show page passes true.
    def initialize(deck:, edit_frame: nil, size: :sm, share: false)
      @deck = deck
      @edit_frame = edit_frame
      @size = size
      @share = share
    end

    def view_template
      div(class: "dropdown", data: { controller: "dropdown" }) do
        button(class: button_class, data: { action: "dropdown#toggle" }) { "Actions ▾" }
        div(class: "dropdown-menu", data: { dropdown_target: "menu" }) do
          edit_item
          share_item if @share
          duplicate_item
          delete_item
        end
      end
    end

    private

    def button_class
      [ "btn", "btn-secondary", ("btn-#{@size}" if @size) ].compact.join(" ")
    end

    def share_item
      button(class: "dropdown-item", data: { action: "share-modal#open" }) { "Share…" }
    end

    def edit_item
      link_opts = { class: "dropdown-item" }
      link_opts[:data] = { turbo_frame: @edit_frame } if @edit_frame
      link_to "Edit", edit_deck_path(@deck), **link_opts
    end

    # Duplicate and Delete always redirect to a full page (the new deck, the index),
    # so they must break out of any enclosing Turbo Frame — the decks index renders
    # this dropdown inside deck_results, where an in-frame response would swap the
    # grid for "Content missing" and swallow the flash. For button_to the `data:`
    # option lands on the <button>, so the frame target goes on the generated form.
    # Outside a frame (the deck show page) "_top" is already the default, so it is
    # safe to hardcode here.
    def duplicate_item
      button_to "Duplicate", duplicate_deck_path(@deck),
        method: :post,
        class: "dropdown-item",
        form: { class: "dropdown-item-form", data: { turbo_frame: "_top" } }
    end

    def delete_item
      button_to "Delete", deck_path(@deck),
        method: :delete,
        class: "dropdown-item dropdown-item-danger",
        form: { class: "dropdown-item-form", data: { turbo_frame: "_top", turbo_confirm: "Delete this deck? Cards and results will be permanently removed." } }
    end
  end
end
