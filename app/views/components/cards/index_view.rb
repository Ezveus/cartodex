module Cards
  class IndexView < ApplicationComponent
    def initialize(blocks:, current_set:, cards:)
      @blocks = blocks
      @current_set = current_set
      @cards = cards
    end

    def view_template
      div(class: "cards-container") do
        h1 { "Cards" }
        div(class: "cards-layout") do
          sidebar
          grid_area
        end
      end
    end

    private

    def sidebar
      nav(class: "sets-sidebar") do
        @blocks.each do |block_name, sets|
          div(class: "sets-block") do
            h3(class: "sets-block-name") { block_name }
            ul(class: "sets-list") do
              sets.each do |card_set|
                li(class: ("active" if @current_set == card_set)) do
                  link_to helpers.cards_path(set: card_set.code) do
                    span(class: "set-full-name") { card_set.name }
                    span(class: "set-code") { "#{card_set.code} (#{card_set.cards.size})" }
                  end
                end
              end
            end
          end
        end
      end
    end

    def grid_area
      div(class: "cards-grid-area") do
        if @current_set
          h2 { @current_set.name }
          div(class: "cards-grid") do
            @cards.each do |card|
              link_to helpers.card_path(card), class: "card-grid-item" do
                if card.image_url.present?
                  image_tag card.image_url, alt: card.name, class: "card-grid-image", loading: "lazy"
                end
                span(class: "card-grid-name") { card.name }
                span(class: "card-grid-number") { "##{card.set_number}" }
              end
            end
          end
        else
          p(class: "cards-empty") { "Select a set to browse cards." }
        end
      end
    end
  end
end
