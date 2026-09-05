module Archetypes
  # The archetype catalog. The shape tournaments#index established, down to the frame id: a
  # debounced search field *outside* the Turbo Frame, table and pager inside it, row links
  # carrying data-turbo-frame="_top".
  class IndexView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "archetype_results".freeze
    COLUMNS = [ "Archetype", "Cards", "Standings", "Events", "Lists", "Last event" ].freeze
    # Zero prints as an em dash rather than as "0": this table's whole point is telling the
    # archetypes Cartodex has recorded something about from the ones it has not, and a column of
    # zeroes reads as data.
    DASH = "—".freeze

    def initialize(archetypes:, counts:, query: "", page: 1, pages: 1)
      @archetypes = archetypes
      @counts = counts
      @query = query
      @page = page
      @pages = pages
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Archetypes")

        search_form

        # Rows and pager inside the frame, the search field outside it: a keystroke pays the
        # pager's COUNT and one page of rows, not the whole surrounding page. Everything inside
        # is frame-scoped by default, so the row links need data-turbo-frame="_top" or a click
        # swaps the table for "Content missing".
        turbo_frame_tag(FRAME_ID) do
          if @archetypes.any?
            render Ui::DataTable.new(columns: COLUMNS) do |t|
              @archetypes.each { |archetype| row(t, archetype) }
            end
            pagination
          else
            p(class: "empty-state") do
              @query.present? ? "No archetypes match this search." : "No archetypes recorded yet."
            end
          end
        end
      end
    end

    private

    def row(table, archetype)
      counts = @counts[archetype.id] || Archetypes::IndexCounts::Counts.zero

      table.row do
        table.cell do
          # The whole cell is the link, so the badge is rendered plain inside it rather than
          # given an href of its own — a nested <a> is invalid markup and Turbo would have two
          # targets to choose between.
          link_to archetype_path(archetype), data: { turbo_frame: "_top" } do
            render Ui::ArchetypeBadge.new(archetype: archetype)
          end
        end
        table.cell { member_cards(archetype) }
        table.cell { number(counts.standings) }
        table.cell { number(counts.events) }
        table.cell { number(counts.lists) }
        table.cell { counts.last_event_on ? localize(counts.last_event_on, format: :long) : DASH }
      end
    end

    # Both printings, never the bare names: several cards share a name and an archetype
    # designates one of them, so this column says which — the rule Card#printing_label exists for.
    def member_cards(archetype)
      div(class: "archetype-member-cards") do
        span { archetype.primary_card.printing_label }
        span { archetype.secondary_card.printing_label } if archetype.secondary_card
      end
    end

    def number(value) = value.to_i.zero? ? DASH : value.to_s

    def search_form
      form(
        action: archetypes_path,
        method: "get",
        class: "archetypes-search",
        data: { controller: "card-filter", turbo_frame: FRAME_ID, turbo_action: "replace" }
      ) do
        input(
          type: "search",
          name: "q",
          value: @query,
          placeholder: "Archetype or card name…",
          class: "form-input",
          autocomplete: "off",
          aria_label: "Search archetypes",
          data: { action: "input->card-filter#debounce" }
        )
      end
    end

    # These links sit inside FRAME_ID, so Turbo navigates the frame and leaves the address bar
    # behind; turbo_action "replace" is what puts ?page= into it at all.
    def pagination
      render Ui::Pagination.new(
        page: @page, pages: @pages, turbo_action: "replace",
        href: ->(page) { archetypes_path(q: @query.presence, page: page) }
      )
    end
  end
end
