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
          # The link is the badge and nothing else — the note below it is deliberately outside,
          # since it is not part of what the reader is clicking. The badge is rendered plain
          # inside the link rather than given an href of its own: a nested <a> is invalid markup
          # and Turbo would have two targets to choose between.
          #
          # The wrapper is load-bearing, not decorative: below 768px .data-table turns each row
          # into a card and its cells into `display: flex; align-items: center`, so a link and a
          # note placed directly in the cell become sibling flex items on one line — the note
          # right-aligned to the card's edge, the badge wrapped to three lines, the row grown from
          # 29px to 64px. A margin cannot fix that. Only a system test can see it, which is why
          # archetype_metagame_test.rb now measures the two bounding boxes.
          div(class: "archetype-row-cell") do
            link_to archetype_path(archetype), data: { turbo_frame: "_top" } do
              render Ui::ArchetypeBadge.new(archetype: archetype)
            end
            online_note(counts)
          end
        end
        table.cell { member_cards(archetype) }
        table.cell { number(counts.standings) }
        table.cell { number(counts.events) }
        table.cell { number(counts.lists) }
        table.cell { counts.last_event_on ? localize(counts.last_event_on, format: :long) : DASH }
      end
    end

    # Outside the row's link and under the badge, because it qualifies the *row* and not any one
    # of its four figures: an imported online event contributes a standing, a distinct event, a
    # list and possibly the latest date, so a note beside "Standings" would imply "Events" is
    # clean — and on the first archetype to carry both, Events is the figure the blend distorts
    # most (13 of 16). The detail page is where the composition is broken down per sample; this
    # only has to stop a reader taking the row for a record of real events, and stop the index's
    # ordering — by standings count — reading as a statement about attendance.
    #
    # Silent at zero, unlike the DASH the number columns print: an em dash there says "nothing
    # recorded", which is information the reader asked for by looking at the column, while a row
    # with no online results has nothing to qualify and 61 of 62 archetypes are that row.
    def online_note(counts)
      return unless counts.online?

      p(class: "archetype-row-note") { online_sentence(counts) }
    end

    # Names the *events* as well as the results, because one number alone invites the wrong ratio.
    # Measured on the first archetype to carry both sources: 106 standings of which 13 are online
    # (12 %) but 16 events of which 13 are (81 %) — a reader given "13" beside a row reading
    # "Standings 106 · Events 16" maps it onto the larger figure and concludes the blend is
    # marginal, when the events column is four fifths online and the "Last event" date is an online
    # weekly.
    #
    # The all-online case gets its own sentence rather than an "Includes" that states a mixture
    # which does not exist — the shape one online import produces for an archetype with no paper
    # results, and the same branch Performance::Result#all_events_online? draws on the detail page.
    # "standings" and not "results": it is the word the column header beside it uses and the word
    # the archetype's own page uses, and three nouns for one thing across one feature is how a
    # reader stops being sure they are the same thing.
    def online_sentence(counts)
      return "Every one of these #{counts.standings} standings comes from online play." if
        counts.online_standings == counts.standings

      "Includes #{counts.online_standings} #{'standing'.pluralize(counts.online_standings)} " \
        "from online play, at #{counts.online_events} of these #{counts.events} events."
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
