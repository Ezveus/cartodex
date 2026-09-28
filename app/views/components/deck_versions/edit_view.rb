module DeckVersions
  # The date is the only thing about a version that can change: its cards are what was played,
  # and the date is the estimate — the backfill's in particular — that the owner may correct.
  class EditView < ApplicationComponent
    def initialize(deck:, version:)
      @deck = deck
      @version = version
    end

    def view_template
      div(class: "deck-form-container") do
        h1 { "Edit #{@version.label}" }
        p(class: "form-hint") { "#{@deck.name} — #{@version.format_label}" }

        form_with(model: @version, scope: :deck_version, url: deck_version_path(@deck, @version),
                  method: :patch, class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @version)

          render Ui::FormGroup.new(hint: "Moving the date can renumber the versions: they are numbered by date.") do
            f.label :effective_at, "Effective from", class: "form-label"
            f.datetime_local_field :effective_at, class: "form-input", required: true
          end

          div(class: "form-actions deck-form-actions") do
            f.submit "Update version", class: "btn btn-primary"
            link_to "Cancel", deck_versions_path(@deck), class: "btn btn-secondary"
          end
        end
      end
    end
  end
end
