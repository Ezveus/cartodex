module Ui
  # The card preview's hover pane. Above the 768px breakpoint this is what card-preview#show
  # fills; below it, card_preview_controller.js checks window.innerWidth itself and opens
  # Ui::CardPreviewModal instead.
  #
  # Extracted because this markup was a verbatim third copy across Decks::ShowView,
  # Decks::PublicShowView and Decks::CompareView, and card_preview_controller.js reads five
  # targets off it and its modal — image, link, modal, modalImage, modalLink. Renaming one
  # used to mean finding three files and getting all three right.
  #
  # The pane and the modal are two components, not one, because the three callers place them
  # independently: CompareView puts the pane inside .deck-compare-content and the dialog
  # outside it, where the two deck pages emit them adjacently.
  class CardPreview < ApplicationComponent
    def initialize(wrapper_class:)
      @wrapper_class = wrapper_class
    end

    def view_template
      div(class: @wrapper_class) do
        image_tag "", data: { card_preview_target: "image" }, class: "card-preview-image", style: "display: none"
        link_to "View card details", "#", data: { card_preview_target: "link" }, class: "card-preview-link", style: "display: none"
      end
    end
  end
end
