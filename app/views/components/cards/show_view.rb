module Cards
  class ShowView < ApplicationComponent
    def initialize(card:, alt_printings:, collection_quantity: 0)
      @card = card
      @alt_printings = alt_printings
      @collection_quantity = collection_quantity
    end

    def view_template
      div(class: "card-show-container") do
        div(class: "card-show-header") do
          h1 { @card.name }
          div(class: "card-show-header-actions") do
            collection_control
            link_to "Back", :back, class: "btn btn-secondary"
          end
        end
        div(class: "card-show-content") do
          card_image
          div(class: "card-show-details") do
            info_section
            abilities_section
            attacks_section
            effect_section
            alt_printings_section
          end
        end
      end
    end

    private

    def collection_control
      div(
        class: "card-collection-control",
        data: {
          controller: "collection-quantity",
          collection_quantity_card_id_value: @card.id,
          collection_quantity_quantity_value: @collection_quantity,
          collection_quantity_flash_on_change_value: true
        }
      ) do
        button(
          type: "button",
          class: "btn btn-primary",
          data: { collection_quantity_target: "addButton", action: "collection-quantity#increment" }
        ) { "Add to collection" }
        div(
          class: "card-collection-counter",
          data: { collection_quantity_target: "counter" }
        ) do
          span(class: "card-collection-counter-label") { "In collection:" }
          button(
            type: "button",
            class: "btn btn-sm",
            data: { action: "collection-quantity#decrement" },
            aria_label: "Decrement"
          ) { "−" }
          span(class: "card-collection-counter-qty", data: { collection_quantity_target: "qty" }) { @collection_quantity.to_s }
          button(
            type: "button",
            class: "btn btn-sm",
            data: { action: "collection-quantity#increment" },
            aria_label: "Increment"
          ) { "+" }
          button(
            type: "button",
            class: "btn btn-sm btn-danger",
            data: { action: "collection-quantity#remove" }
          ) { "Remove" }
        end
      end
    end

    def card_image
      div(class: "card-show-image") do
        image_tag @card.image_url, alt: @card.name, class: "card-full-image" if @card.image_url.present?
      end
    end

    def info_section
      div(class: "card-info-section") do
        h2 { "Info" }
        dl(class: "card-info-list") do
          info_row("Type", @card.card_type)
          info_row("Subtype", @card.subtype)
          info_row("Stage", @card.stage)
          info_row("HP", @card.hp)
          info_row("Energy Type", @card.type_symbol)
          info_row("Evolves From", @card.evolves_from)
          info_row("Weakness", @card.weakness)
          info_row("Resistance", @card.resistance)
          info_row("Retreat Cost", @card.retreat_cost)
          dt { "Set" }
          dd { "#{@card.set_full_name || @card.set_name} (#{@card.set_number})" }
          info_row("Rarity", @card.rarity)
          info_row("Regulation", @card.regulation_mark)
          info_row("Artist", @card.artist)
          price_row
        end
      end
    end

    def info_row(label, value)
      return unless value.present?
      dt { label }
      dd { value.to_s }
    end

    def price_row
      return unless @card.price_eur.present? || @card.price_usd.present?
      dt { "Price" }
      dd do
        if @card.price_eur.present?
          plain number_to_currency(@card.price_eur, unit: "\u20AC")
        end
        plain " / " if @card.price_eur.present? && @card.price_usd.present?
        if @card.price_usd.present?
          plain number_to_currency(@card.price_usd, unit: "$")
        end
      end
    end

    def abilities_section
      return unless @card.abilities.any?
      div(class: "card-info-section") do
        h2 { "Abilities" }
        @card.abilities.each do |ability|
          render Cards::AbilityItem.new(ability:)
        end
      end
    end

    def attacks_section
      return unless @card.attacks.any?
      div(class: "card-info-section") do
        h2 { "Attacks" }
        @card.attacks.each do |attack|
          render Cards::AttackItem.new(attack:)
        end
      end
    end

    def effect_section
      return unless @card.effect.present?
      div(class: "card-info-section") do
        h2 { "Effect" }
        p { @card.effect }
      end
    end

    def alt_printings_section
      return unless @alt_printings.any?
      div(class: "card-info-section") do
        h2 { "Alternative Printings" }
        div(class: "alt-printings") do
          @alt_printings.each do |alt|
            link_to card_path(alt), class: "alt-printing-item" do
              image_tag alt.image_url, alt: alt.name, class: "alt-printing-image" if alt.image_url.present?
              span(class: "alt-printing-set") { "#{alt.set_full_name || alt.set_name} (#{alt.set_number})" }
            end
          end
        end
      end
    end
  end
end
