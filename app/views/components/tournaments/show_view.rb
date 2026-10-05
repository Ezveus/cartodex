module Tournaments
  # The public face of an event. It shows the event and nothing else: no attendee list, no
  # entry count, no deck anybody played. The only thing it knows about its reader is whether
  # they have a participation of their own to go to.
  class ShowView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    SHEET_FRAME_ID = "tournament_sheet".freeze

    def initialize(tournament:, my_entries: [], standings: [], sheet_page: 1, sheet_pages: 1,
                   sheet_filters: {}, archetype_options: [], division_options: [],
                   can_record: false, can_record_another: false, can_edit: false,
                   can_edit_standings: false, viewer: nil, pending_standing_imports: [],
                   claimable_entries: [])
      @tournament = tournament
      @my_entries = my_entries
      @standings = standings
      @sheet_page = sheet_page
      @sheet_pages = sheet_pages
      @sheet_filters = sheet_filters
      @archetype_options = archetype_options
      @division_options = division_options
      @can_record = can_record
      @can_record_another = can_record_another
      @can_edit = can_edit
      @can_edit_standings = can_edit_standings
      @viewer = viewer
      @pending_standing_imports = pending_standing_imports
      @claimable_entries = claimable_entries
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: @tournament.name) do
          div(class: "decks-header-actions") do
            entry_action
            link_to "Edit", edit_tournament_path(@tournament), class: "btn btn-secondary" if @can_edit
            link_to "Back to Tournaments", tournaments_path, class: "btn btn-secondary"
          end
        end

        render Tournaments::EventDetails.new(tournament: @tournament)
        standings_section
      end
    end

    private

    # The other half of the online withholding above. Every claim affordance on the sheet — the
    # "This is me" button Tournaments::Standings::Row renders on an unclaimed row — is driven by
    # this list, so emptying it here is what stops an online event inviting a participation
    # through the sheet after entry_action stopped inviting one through the header. Emptied in
    # the view and not in the controller for the reason entry_action is guarded there: it is the
    # page that stops proposing, and nothing refuses a member who reaches the route anyway.
    def claimable_entries
      return [] unless invites_participation?

      @claimable_entries
    end

    # The event's public sheet. Public by the same rule the page is: the catalog does not hide an
    # event, so it does not hide what was played there either. Only the write controls are gated.
    def standings_section
      div(class: "tournament-standings") do
        div(class: "admin-header") do
          h2 { "Standings" }
          # "Add a standing" survives on an online event, unlike the three participation
          # invitations above, and the difference is the record each one creates: a participation
          # is an age-division Play! Pokémon record that means nothing online and makes the event
          # undeletable, while a standing is wiki-governed public data on a sheet that arrives
          # imported, de-duplicated and therefore partial — with Edit and Delete already on every
          # row. Tournaments::Standings::Form#offered_divisions is what keeps the row honest once
          # the member is in the form: an online event offers "open" and no age division.
          if @can_edit_standings
            link_to "Add a standing", new_tournament_standing_path(@tournament),
              class: "btn btn-primary btn-sm"
          end
        end

        # The pending state, in Ui::ImportingList's own vocabulary: the item id is
        # importing-<import id>, which is exactly what the import job removes by target when the
        # field list lands.
        render Ui::ImportingList.new(
          pending_imports: @pending_standing_imports,
          item_id_prefix: "importing",
          list_id: "importing-standings"
        )

        # The event's divisions, read off its whole field: none means no standing at all, and
        # then there is nothing to filter.
        if @division_options.empty?
          p(class: "empty-state") { "No standings recorded for this event yet." }
        else
          sheet_filter_bar
          sheet_frame
        end
      end
    end

    # The rows and the pager, and nothing else, so a keystroke in the filter swaps one page of
    # rows instead of visiting the whole page — which would replace the field being typed in and
    # drop its focus. `target: "_top"` is what keeps every link and form *in* the rows (the deck
    # link, Edit, Delete, "This is me", Unlink) navigating the page as it always has, without each
    # one learning data-turbo-frame="_top"; only the pager's two links opt back into the frame.
    def sheet_frame
      turbo_frame_tag(SHEET_FRAME_ID, target: "_top") do
        if @standings.any?
          render Tournaments::Standings::Table.new(
            standings: @standings, viewer: @viewer,
            can_edit: @can_edit_standings, claimable_entries: claimable_entries
          )
          # Inside the frame, so "replace" is what puts ?page= and the filters into the address
          # bar at all — see Ui::Pagination.
          render Ui::Pagination.new(
            page: @sheet_page, pages: @sheet_pages, turbo_action: "replace",
            turbo_frame: SHEET_FRAME_ID,
            href: ->(page) { tournament_path(@tournament, page: page, **@sheet_filters) }
          )
        else
          # Never "No standings recorded for this event yet.": the event has some, this filter
          # matched none of them.
          p(class: "empty-state") { "No standings match these filters." }
        end
      end
    end

    # Player, archetype, division — AND-ed. Outside the frame, so live filtering never re-renders
    # it: the options are the whole event's, and Clear ships in both states for card-filter to
    # flip from the form's own values, the way the deck listings' bar does.
    def sheet_filter_bar
      form(
        action: tournament_path(@tournament),
        method: "get",
        class: "deck-filters",
        data: { controller: "card-filter", turbo_frame: SHEET_FRAME_ID, turbo_action: "replace" }
      ) do
        input(
          type: "search",
          name: "player",
          value: @sheet_filters[:player],
          placeholder: "Player name…",
          class: "form-input deck-filter-search",
          autocomplete: "off",
          aria_label: "Filter by player name",
          data: { action: "input->card-filter#debounce" }
        )
        render Ui::FilterSelect.new(name: :archetype, options: archetype_options,
                                    selected: @sheet_filters[:archetype])
        # One division is no choice: an online event is all "open", and a hand-typed sheet is
        # often masters alone.
        if @division_options.size > 1
          render Ui::FilterSelect.new(name: :division, options: division_options,
                                      selected: @sheet_filters[:division])
        end
        a(
          href: tournament_path(@tournament),
          class: "btn btn-secondary btn-sm",
          hidden: @sheet_filters.empty?,
          data: { card_filter_target: "clear" }
        ) { "Clear" }
      end
    end

    # The slug travels in the URL, not the id: a filtered sheet is a public address worth sharing,
    # and the slug is what an archetype's address already is.
    def archetype_options
      [ [ "All archetypes", "" ] ] + @archetype_options.map { |archetype| [ archetype.name, archetype.slug ] }
    end

    def division_options
      [ [ "All divisions", "" ] ] + @division_options.map { |division| [ division.capitalize, division ] }
    end

    # Two rules meet here. A reader has as many participations as they have Play! Pokémon
    # profiles that attended, so this is a list, not a link — and the "record" button survives
    # alongside it, since a second profile has no other route to a form. A visitor gets none of
    # it: `can_record` guards the whole method rather than the `empty?` branch alone, because a
    # visitor's `my_entries` is `[]` by construction, and "Record your participation" would then
    # be a link to the sign-in page dressed as a primary action. Inviting somebody to sign in is
    # the navbar's job, not this page's.
    #
    # An online event is offered none of the *invitations*, and that is withheld rather than
    # refused: no policy gains a clause and no action redirects, the page simply stops proposing
    # something wrong. Wrong twice over — an online event has no age divisions, so a Play!
    # Pokémon profile has nothing to attach to, and `Tournament has_many :entries, dependent:
    # :restrict_with_error` means one member accepting the invitation makes an imported event
    # permanently undeletable. A participation the reader somehow already has keeps its link,
    # though: hiding it would put their own record out of reach of the only page that leads to
    # it, which is the bug the plural my_entries above exists to have fixed.
    def entry_action
      return unless @can_record

      if @my_entries.empty?
        return unless invites_participation?

        link_to "Record your participation", new_tournament_entry_path(@tournament), class: "btn btn-primary"
        return
      end

      @my_entries.each do |entry|
        link_to entry_label(entry), tournament_entry_path(@tournament, entry), class: "btn btn-primary"
      end
      return unless invites_participation?

      publish_actions
      return unless @can_record_another

      link_to "Record another participation", new_tournament_entry_path(@tournament), class: "btn btn-secondary"
    end

    def invites_participation? = !@tournament.online?

    # One participation needs no disambiguation and naming the profile would be noise; two need
    # it, and the player name is the only thing that tells them apart.
    def entry_label(entry)
      return "Your entry" if @my_entries.one?

      player_name = entry.tournament_profile&.player_name
      player_name ? "Your entry (#{player_name})" : "Your entry (no profile)"
    end

    # One per participation the reader owns that no standing names yet. Guarded by the same
    # can_record as the buttons above, for the same reason: a visitor's my_entries is [] by
    # construction, so the loop is empty for them anyway — but the guard is what says the whole
    # block belongs to a reader who may write, rather than resting on that emptiness.
    def publish_actions
      @claimable_entries.each do |entry|
        link_to publish_label(entry),
          new_tournament_standing_path(@tournament, tournament_entry_id: entry.id),
          class: "btn btn-secondary"
      end
    end

    # One button needs no disambiguation; two or more do, and the player name is the only thing
    # that tells them apart. Keyed on @claimable_entries, the collection this method's own caller
    # (publish_actions) iterates — not on @my_entries, which entry_label above uses because *it*
    # iterates @my_entries. The two collections can disagree: once one of a reader's two entries
    # is already published, @claimable_entries drops to one while @my_entries stays at two, and a
    # label keyed on the wrong collection would name a player nobody needs named for the single
    # remaining button.
    def publish_label(entry)
      return "Publish my participation" if @claimable_entries.one?

      name = entry.tournament_profile&.player_name
      name ? "Publish #{name}'s participation" : "Publish my participation (no profile)"
    end
  end
end
