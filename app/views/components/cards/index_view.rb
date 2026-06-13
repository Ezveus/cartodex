module Cards
  class IndexView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "card_results".freeze

    def initialize(blocks:, current_set:, cards:, query:, type:, energy:, rarity:, mark:, rarities:, marks:, searching:, total: nil, page: 1, pages: nil)
      @blocks = blocks
      @current_set = current_set
      @cards = cards
      @query = query
      @type = type
      @energy = energy
      @rarity = rarity
      @mark = mark
      @rarities = rarities
      @marks = marks
      @searching = searching
      @total = total
      @page = page
      @pages = pages
    end

    def view_template
      div(class: "cards-container") do
        h1 { "Cards" }
        search_bar
        div(class: "cards-layout") do
          sidebar
          grid_area
        end
      end
    end

    private

    def search_bar
      form(
        action: cards_path,
        method: "get",
        class: "cards-search",
        data: { controller: "card-filter", turbo_frame: FRAME_ID, turbo_action: "replace" }
      ) do
        input(
          type: "search",
          name: "q",
          value: @query,
          placeholder: "Search by name, e.g. “Pikachu SVI 25”…",
          class: "form-input cards-search-input",
          autocomplete: "off",
          data: { action: "input->card-filter#debounce" }
        )
        filter_select("type", "Type", Card::CARD_TYPES, @type)
        filter_select("energy", "Energy", Card::ENERGY_TYPES, @energy)
        filter_select("rarity", "Rarity", @rarities, @rarity)
        filter_select("mark", "Mark", @marks, @mark)
        set_select
      end
    end

    def filter_select(name, all_label, options, selected)
      select(name: name, class: "form-input cards-search-select", data: { action: "change->card-filter#submit" }) do
        option(value: "") { "All #{all_label}" }
        options.each do |value|
          option(value: value, selected: value == selected) { value }
        end
      end
    end

    def set_select
      select(name: "set", class: "form-input cards-search-select", data: { action: "change->card-filter#submit" }) do
        option(value: "") { "All sets" }
        @blocks.each do |block_name, sets|
          optgroup(label: block_name) do
            sets.each do |card_set|
              option(value: card_set.code, selected: @current_set == card_set) { card_set.name }
            end
          end
        end
      end
    end

    def sidebar
      nav(class: "sets-sidebar") do
        @blocks.each do |block_name, sets|
          div(class: "sets-block") do
            h3(class: "sets-block-name") { block_name }
            ul(class: "sets-list") do
              sets.each do |card_set|
                li(class: ("active" if @current_set == card_set)) do
                  link_to cards_path(set: card_set.code) do
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
        turbo_frame_tag(FRAME_ID) do
          if @searching
            search_results
          elsif @current_set
            h2 { @current_set.name }
            cards_grid
          else
            p(class: "cards-empty") { "Select a set or search to browse cards." }
          end
        end
      end
    end

    def search_results
      if @cards.any?
        h2 { "Results" }
        count = @total || @cards.size
        p(class: "cards-search-count") { "#{count} #{count == 1 ? "match" : "matches"}" }
        cards_grid
        pagination_controls
      else
        p(class: "cards-empty") { "No cards match your search." }
      end
    end

    def pagination_controls
      return unless @pages && @pages > 1

      div(class: "cards-pagination") do
        if @page > 1
          link_to cards_path(**search_query_params, page: @page - 1),
                  class: "cards-pagination-link",
                  data: { turbo_action: "replace" } do
            "← Previous"
          end
        end
        span(class: "cards-pagination-info") { "Page #{@page} / #{@pages}" }
        if @page < @pages
          link_to cards_path(**search_query_params, page: @page + 1),
                  class: "cards-pagination-link",
                  data: { turbo_action: "replace" } do
            "Next →"
          end
        end
      end
    end

    def search_query_params
      {
        q: @query.presence,
        type: @type,
        energy: @energy,
        rarity: @rarity,
        mark: @mark,
        set: @current_set&.code
      }.compact
    end

    def cards_grid
      div(class: "cards-grid") do
        @cards.each do |card|
          link_to card_path(card), class: "card-grid-item", data: { turbo_frame: "_top" } do
            if card.image_url.present?
              image_tag card.image_url, alt: card.name, class: "card-grid-image", loading: "lazy"
            end
            span(class: "card-grid-name") { card.name }
            span(class: "card-grid-number") { "##{card.set_number}" }
          end
        end
      end
    end
  end
end
