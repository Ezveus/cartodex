module Decks
  # What the Share dialog contains and what PATCH /decks/:key/share re-renders: the toggle, the
  # sentence that says sharing means publishing, and — once shared — the link to copy.
  class ShareFrame < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "deck-share".freeze

    def initialize(deck:)
      @deck = deck
    end

    def view_template
      # Inside the dialog, so the PATCH swaps the toggle and the link without closing what the
      # user is looking at.
      turbo_frame_tag(FRAME_ID) do
        # The card-filter controller is reused for its `submit` action (a requestSubmit on the
        # form): the app carries no inline event handlers, and this form needs nothing more.
        form_with url: share_deck_path(@deck), method: :patch,
                  data: { turbo_frame: FRAME_ID, controller: "card-filter" } do
          # The hidden "0" is what the form-builder `check_box` adds and a bare checkbox does
          # not. Without it an unchecked box posts nothing, and nothing casts to nil against a
          # NOT NULL column. Plain Phlex tags: ApplicationComponent includes FormWith but none
          # of the *_tag helpers, and these need nothing a helper would add.
          input(type: "hidden", name: "shared", value: "0")
          input(
            type: "checkbox", name: "shared", value: "1", id: "shared", checked: @deck.shared?,
            data: { action: "change->card-filter#submit" }
          )
          label(for: "shared") { "Share this deck publicly" }
        end

        # Sharing publishes: the deck is listed at /decks/shared, not merely reachable by
        # anyone holding a link. Say so, and say what becomes visible — the description in
        # particular is free text often written while the deck was private.
        p(class: "share-explainer") do
          plain "A shared deck is listed publicly on the shared decks page. Its name, " \
                "description, format, archetype and card list become visible to anyone. " \
                "Your results, your collection and your proxy counts do not."
        end

        share_link if @deck.shared?
      end
    end

    private

    def share_link
      div(class: "share-link") do
        input(type: "text", id: "share-url", value: deck_url(@deck), readonly: true, class: "form-input")
        button(
          class: "btn btn-secondary btn-sm",
          data: { controller: "clipboard", clipboard_text_value: deck_url(@deck), action: "clipboard#copy" }
        ) { "Copy link" }
      end
    end
  end
end
