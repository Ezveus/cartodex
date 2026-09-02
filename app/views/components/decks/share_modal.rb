module Decks
  # The Share dialog. A <dialog> with a target the share-modal controller opens, like
  # Decks::ResultModal — not Ui::Modal, which is a div whose display another controller flips.
  #
  # The dialog and its frame are two components on purpose: the PATCH answers with a Turbo
  # Stream that replaces the frame, and a stream that rendered this component would drop a
  # second, closed <dialog> inside the open one. Only Decks::ShareFrame is ever re-rendered.
  class ShareModal < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      dialog(class: "share-modal", data: { share_modal_target: "dialog" }) do
        div(class: "share-modal-content") do
          h2 { "Share this deck" }
          render Decks::ShareFrame.new(deck: @deck)
          button(class: "btn btn-secondary btn-sm", data: { action: "share-modal#close" }) { "Close" }
        end
      end
    end
  end
end
