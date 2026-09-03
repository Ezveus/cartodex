module Ui
  # What the card preview becomes below the 768px breakpoint: a full-screen <dialog> whose
  # backdrop eats subsequent clicks (which is why test/system/card_preview_modal_test.rb
  # exists at all). See Ui::CardPreview for why the pane and the dialog are two components.
  class CardPreviewModal < ApplicationComponent
    def view_template
      dialog(
        class: "card-preview-modal",
        data: {
          card_preview_target: "modal",
          action: "click->card-preview#backdropClose"
        }
      ) do
        div(class: "card-preview-modal-content") do
          image_tag "", data: { card_preview_target: "modalImage" }, class: "card-preview-modal-image"
          link_to "View card details", "#", data: { card_preview_target: "modalLink" }, class: "btn btn-secondary btn-sm"
          button(class: "btn btn-sm", data: { action: "card-preview#closeModal" }) { "Close" }
        end
      end
    end
  end
end
