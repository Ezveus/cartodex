module Collections
  class IndexView < ApplicationComponent
    def initialize(collections:, card_sets:, card_types:, selected_set_code:, selected_type:, query:, total_unique:, total_copies:)
      @collections = collections
      @card_sets = card_sets
      @card_types = card_types
      @selected_set_code = selected_set_code
      @selected_type = selected_type
      @query = query
      @total_unique = total_unique
      @total_copies = total_copies
    end

    def view_template
      div(class: "collection-container") do
        header_section
        filters_section
        results_section
      end
    end

    private

    def header_section
      div(class: "collection-header") do
        h1 { "My Collection" }
        div(class: "collection-stats") do
          render Ui::Stat.new(value: @total_unique, label: "unique")
          render Ui::Stat.new(value: @total_copies, label: "copies")
        end
      end
    end

    def filters_section
      form_with(url: collections_path, method: :get, local: true, class: "collection-filters") do
        div(class: "form-group collection-filter-search") do
          label(class: "form-label", for: "collection-q") { "Search" }
          input(type: "text", name: "q", id: "collection-q", value: @query, class: "form-input", placeholder: "Card name...")
        end

        div(class: "form-group") do
          label(class: "form-label", for: "collection-set") { "Set" }
          select(name: "set", id: "collection-set", class: "form-input") do
            option(value: "") { "All sets" }
            @card_sets.each do |card_set|
              option_attrs = { value: card_set.code }
              option_attrs[:selected] = "selected" if card_set.code == @selected_set_code
              option(**option_attrs) { "#{card_set.name} (#{card_set.code})" }
            end
          end
        end

        div(class: "form-group") do
          label(class: "form-label", for: "collection-type") { "Type" }
          select(name: "type", id: "collection-type", class: "form-input") do
            option(value: "") { "All types" }
            @card_types.each do |type|
              option_attrs = { value: type }
              option_attrs[:selected] = "selected" if type == @selected_type
              option(**option_attrs) { type }
            end
          end
        end

        div(class: "collection-filter-actions") do
          button(type: "submit", class: "btn btn-primary") { "Apply" }
          link_to "Clear", collections_path, class: "btn btn-secondary"
        end
      end
    end

    def results_section
      div(data: {
        controller: "collection-list",
        action: "collection-quantity:removed->collection-list#removed"
      }) do
        div(class: "collection-grid", data: { collection_list_target: "grid" }) do
          @collections.each { |collection| collection_tile(collection) }
        end
        p(
          class: "collection-empty",
          data: { collection_list_target: "empty" },
          style: ("display: none" if @collections.any?)
        ) { empty_message }
      end
    end

    def empty_message
      if filters_active?
        "No cards match these filters."
      else
        "Your collection is empty. Add cards from the Cards page."
      end
    end

    def filters_active?
      @query.present? || @selected_set_code.present? || @selected_type.present?
    end

    def collection_tile(collection)
      card = collection.card
      div(
        class: "collection-tile",
        data: {
          controller: "collection-quantity",
          collection_quantity_card_id_value: card.id,
          collection_quantity_quantity_value: collection.quantity
        }
      ) do
        link_to card_path(card), class: "collection-tile-link" do
          if card.image_url.present?
            image_tag card.image_url, alt: card.name, class: "collection-tile-image", loading: "lazy"
          end
          span(class: "collection-tile-name") { card.name }
          span(class: "collection-tile-meta") { "#{card.set_name} ##{card.set_number}" }
        end

        div(class: "collection-tile-controls") do
          button(
            type: "button",
            class: "btn btn-sm",
            data: { action: "collection-quantity#decrement" },
            aria_label: "Decrement"
          ) { "−" }
          span(class: "collection-tile-qty", data: { collection_quantity_target: "qty" }) { collection.quantity.to_s }
          button(
            type: "button",
            class: "btn btn-sm",
            data: { action: "collection-quantity#increment" },
            aria_label: "Increment"
          ) { "+" }
          button(
            type: "button",
            class: "btn btn-sm btn-danger",
            data: { action: "collection-quantity#remove" },
            aria_label: "Remove"
          ) { "Remove" }
        end
      end
    end
  end
end
