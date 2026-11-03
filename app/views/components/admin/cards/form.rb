module Admin
  module Cards
    # Shared by create and edit. A Pokémon's fingerprint hashes its attacks and abilities, so the
    # form carries them as fixed slots: a card saved without them would fingerprint like a card
    # that has none.
    class Form < ApplicationComponent
      def initialize(card:, attacks:, abilities:, url:, submit_label:, cancel_path:)
        @card = card
        @attacks = attacks
        @abilities = abilities
        @url = url
        @submit_label = submit_label
        @cancel_path = cancel_path
      end

      def view_template
        form_with(model: @card, url: @url, scope: :card, class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @card)

          text_group(f, :name)
          select_group(f, :card_type, Card::CARD_TYPES)
          select_group(f, :stage, Card::STAGES)
          select_group(f, :subtype, Card::SUBTYPES)
          text_group(f, :evolves_from)
          render Ui::FormGroup.new do
            f.label :hp, "HP", class: "form-label"
            f.number_field :hp, class: "form-input"
          end
          select_group(f, :type_symbol, Card::ENERGY_TYPES, label: "Energy Type")
          text_group(f, :weakness)
          text_group(f, :resistance)
          # Pokémon-only, but presence-validated: without this field a card switched
          # to "Pokémon" could never be saved from here.
          render Ui::FormGroup.new do
            f.label :retreat_cost, class: "form-label"
            f.number_field :retreat_cost, min: 0, class: "form-input"
          end
          text_group(f, :rarity)
          text_group(f, :regulation_mark)
          set_code_group(f)
          text_group(f, :set_number)
          # On create the set is the page's, so the select would only offer a value the controller
          # ignores.
          if @card.persisted?
            render Ui::FormGroup.new do
              f.label :card_set_id, "Card Set", class: "form-label"
              f.collection_select :card_set_id, CardSet.order(:name), :id, :name, { include_blank: "— None —" }, class: "form-input"
            end
          end
          text_group(f, :artist)
          text_group(f, :image_url, label: "Image URL")
          render Ui::FormGroup.new do
            f.label :effect, class: "form-label"
            f.text_area :effect, rows: 3, class: "form-input"
          end

          attack_slots
          ability_slots

          div(class: "form-actions deck-form-actions") do
            f.submit @submit_label, class: "btn btn-primary"
            link_to "Cancel", @cancel_path, class: "btn btn-secondary"
          end
        end
      end

      private

      def text_group(form, attribute, label: nil)
        render Ui::FormGroup.new do
          form.label attribute, label, class: "form-label"
          form.text_field attribute, class: "form-input"
        end
      end

      # On create the code is the set's and the controller ignores a posted one, so it is shown but
      # carries no name: an editable field would invite a value that is silently dropped.
      def set_code_group(form)
        return text_group(form, :set_name, label: "Set Code") if @card.persisted?

        render Ui::FormGroup.new(label: "Set Code", field_name: "card_set_name") do
          input(type: "text", id: "card_set_name", value: @card.set_name.to_s, readonly: true, class: "form-input")
        end
      end

      # A value outside the list stays an option, or editing such a card would silently blank it.
      def select_group(form, attribute, choices, label: nil)
        current = @card.public_send(attribute)
        choices += [ current ] if current.present? && choices.exclude?(current)
        render Ui::FormGroup.new do
          form.label attribute, label, class: "form-label"
          form.select attribute, choices, { include_blank: true }, class: "form-input"
        end
      end

      # Never fewer slots than the card holds, so an edit cannot drop one.
      def attack_slots
        count = [ ::Cards::ManualWriter::ATTACK_SLOTS, @attacks.size ].max
        fieldset(class: "form-fieldset") do
          legend(class: "form-label") { "Attacks" }
          count.times do |index|
            slot = @attacks[index] || {}
            div(class: "form-group") do
              slot_input("attacks", index, "name", slot, label: "Attack #{index + 1} name")
              slot_input("attacks", index, "cost", slot, label: "Cost")
              slot_input("attacks", index, "damage", slot, label: "Damage")
              slot_textarea("attacks", index, "effect", slot, label: "Effect")
            end
          end
        end
      end

      def ability_slots
        count = [ ::Cards::ManualWriter::ABILITY_SLOTS, @abilities.size ].max
        fieldset(class: "form-fieldset") do
          legend(class: "form-label") { "Abilities" }
          count.times do |index|
            slot = @abilities[index] || {}
            div(class: "form-group") do
              slot_input("abilities", index, "name", slot, label: "Ability #{index + 1} name")
              slot_textarea("abilities", index, "effect", slot, label: "Effect")
            end
          end
        end
      end

      # String names, built by hand: a Symbol value would be dasherized by Phlex (phlex-architecture).
      def slot_input(group, index, field, slot, label:)
        id = "card_#{group}_#{index}_#{field}"
        label(class: "form-label", for: id) { label }
        input(type: "text", id:, name: "card[#{group}][#{index}][#{field}]", value: slot[field].to_s, class: "form-input")
      end

      def slot_textarea(group, index, field, slot, label:)
        id = "card_#{group}_#{index}_#{field}"
        label(class: "form-label", for: id) { label }
        textarea(id:, name: "card[#{group}][#{index}][#{field}]", rows: 2, class: "form-input") { slot[field].to_s }
      end
    end
  end
end
