module Decks
  class HeaderFrame < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "deck-header".freeze

    # `group` is the owner page's list view (see Decks::ShowView::GROUPINGS). Only this frame is
    # replaced on Edit, Save and Cancel, so the list keeps its view anyway; the form and Cancel carry
    # it for the full-page case — the edit page opened in a tab of its own, and its 422 re-render.
    def initialize(deck:, editing: false, group: :type)
      @deck = deck
      @editing = editing
      @group = group
    end

    def view_template
      turbo_frame_tag(FRAME_ID) do
        if @editing
          edit_form
        else
          display
        end
      end
    end

    private

    def display
      div do
        h1 { @deck.name }
        # `linked`: this row sits in a plain div here, so the archetype badge can be an anchor.
        # Decks::DeckCard renders the same row inside its own link and must not — see the note on
        # ClassificationBadges#initialize.
        render Decks::ClassificationBadges.new(deck: @deck, live: true, linked: true)
        p(class: "deck-show-description") { @deck.description } if @deck.description.present?
      end
    end

    def edit_form
      form_with(model: @deck, url: deck_path(@deck, group: group_param), class: "deck-header-form") do |f|
        render Ui::FormErrors.new(resource: @deck)

        f.text_field :name, class: "form-input deck-header-name-input", autofocus: true, placeholder: "Deck name"
        f.text_area :description, class: "form-input deck-header-description-input", rows: 2, placeholder: "Description (optional)"

        render Decks::ClassificationFields.new(form: f, deck: @deck)

        div(class: "deck-header-form-actions") do
          f.submit "Save", class: "btn btn-primary btn-sm"
          link_to "Cancel", deck_path(@deck, group: group_param), class: "btn btn-secondary btn-sm", data: { turbo_frame: FRAME_ID }
        end
      end
    end

    # Nil in the default view, which URL helpers drop: the type view's links stay what they were.
    def group_param = (@group == :set ? "set" : nil)
  end
end
