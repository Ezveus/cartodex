module DeckVersions
  # Reconstructing a list the deck no longer holds, from a pasted decklist. Plain tags with
  # String names rather than a model form: the decklist is not an attribute of anything, and a
  # refusal re-renders the reader's own strings as they typed them.
  class NewView < ApplicationComponent
    PLACEHOLDER = "4 Honedge POR 56\n2 Doublade POR 57\n…".freeze

    def initialize(deck:, form:, errors:, standard_pools:)
      @deck = deck
      @form = form.to_h.with_indifferent_access
      @errors = errors
      @standard_pools = standard_pools
    end

    def view_template
      div(class: "deck-form-container") do
        h1 { "Add an earlier version" }
        p(class: "form-hint") do
          "A list #{@deck.name} was played with before its current one. Every card must already " \
            "be in the catalogue; one line it cannot read refuses the whole list."
        end

        form_with(url: deck_versions_path(@deck), method: :post, class: "deck-form") do
          errors_block

          decklist_group
          effective_at_group
          format_group
          standard_pool_group
          other_format_group

          div(class: "form-actions deck-form-actions") do
            button(type: "submit", class: "btn btn-primary") { "Create version" }
            link_to "Cancel", deck_versions_path(@deck), class: "btn btn-secondary"
          end
        end
      end
    end

    private

    # The importer's refusals are strings, not model errors, so Ui::FormErrors cannot take them;
    # this is its markup.
    def errors_block
      return if @errors.blank?

      div(class: "form-errors") do
        h3 { "#{@errors.size} #{@errors.size == 1 ? 'error' : 'errors'} prohibited this action:" }
        ul { @errors.each { |message| li { message } } }
      end
    end

    def decklist_group
      render Ui::FormGroup.new(label: "Decklist", field_name: "deck_version_decklist",
                               hint: "One card per line: quantity, name, set code, number.") do
        textarea(name: "deck_version[decklist]", id: "deck_version_decklist", class: "form-input",
                 rows: "14", placeholder: PLACEHOLDER) { @form[:decklist].to_s }
      end
    end

    def effective_at_group
      render Ui::FormGroup.new(label: "Effective from", field_name: "deck_version_effective_at",
                               hint: "When the deck started being played with this list.") do
        input(type: "datetime-local", name: "deck_version[effective_at]", id: "deck_version_effective_at",
              class: "form-input", value: @form[:effective_at].to_s, required: true)
      end
    end

    def format_group
      render Ui::FormGroup.new(label: "Format", field_name: "deck_version_format") do
        select(name: "deck_version[format]", id: "deck_version_format", class: "form-input") do
          Deck::FORMAT_LABELS.each do |value, label|
            option(value: value, selected: value == selected_format) { label }
          end
        end
      end
    end

    # Both conditional fields are always shown, with a hint, the way the tournament form does it:
    # the server ignores the one the format does not use, and a toggle would be a second copy of
    # that rule in JS.
    def standard_pool_group
      render Ui::FormGroup.new(label: "Standard pool", field_name: "deck_version_standard_pool_id",
                               hint: "Only used when format is “Standard”") do
        select(name: "deck_version[standard_pool_id]", id: "deck_version_standard_pool_id", class: "form-input") do
          @standard_pools.each do |pool|
            option(value: pool.id.to_s, selected: pool.id.to_s == selected_pool_id) { pool.name }
          end
        end
      end
    end

    def other_format_group
      render Ui::FormGroup.new(label: "Format name", field_name: "deck_version_other_format_name",
                               hint: "Only used when format is “Other”") do
        input(type: "text", name: "deck_version[other_format_name]", id: "deck_version_other_format_name",
              class: "form-input", value: @form[:other_format_name].to_s, placeholder: "e.g. Pocket, Theme…")
      end
    end

    # A blank form starts from the deck's own classification, which is the likeliest answer for a
    # list it held before.
    def selected_format
      @form[:format].presence || @deck.format
    end

    def selected_pool_id
      (@form[:standard_pool_id].presence || @deck.standard_pool_id).to_s
    end
  end
end
