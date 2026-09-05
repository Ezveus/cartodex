module Tournaments
  module Standings
    # One line of the sheet — and the unit a finished field-list import replaces over Turbo
    # Streams, which is why it renders its own `.data-table-row` instead of taking Ui::DataTable's
    # yielded builder: a row that only exists inside that block could not be rendered alone.
    # COLUMNS is shared with Table so the header and these cells' data-labels cannot drift.
    class Row < ApplicationComponent
      COLUMNS = [ "#", "Player", "Archetype", "Record", "List", "" ].freeze

      def self.dom_id(standing) = "standing-#{standing.id}"

      # Where this row lives in the sheet, as options for tournament_path. Three callers need it —
      # the controller's redirects after a write, the duplicate-name hint on the form, and Cancel —
      # and each of them used to point at the event, which was the same place as the row until the
      # sheet grew a pager. It lives beside dom_id because the anchor *is* the row's identity, and
      # in one place because three copies of "which page is it on" drift.
      #
      # nil for page one, so the ordinary case keeps the bare, shareable URL it has always had:
      # url_for drops a nil param.
      def self.sheet_position(standing)
        page = TournamentStanding.page_of(standing)
        { page: (page unless page == 1), anchor: dom_id(standing) }
      end

      def initialize(standing:, viewer: nil, can_edit: false, claimable_entries: [])
        @standing = standing
        @viewer = viewer
        @can_edit = can_edit
        @claimable_entries = claimable_entries
      end

      def view_template
        div(class: "data-table-row", id: self.class.dom_id(@standing)) do
          cell(0) { @standing.placement ? "##{@standing.placement}" : "—" }
          cell(1) do
            plain @standing.player_name
            # The badge, not a sentence: the cell is narrow and the marker only has to be
            # recognisable to the one reader it applies to.
            span(class: "badge badge-archetype") { "You" } if mine?
          end
          cell(2) { archetype_badge }
          cell(3) { @standing.record_label || "—" }
          cell(4) { list_link }
          cell(5) { actions }
        end
      end

      private

      # Ui::DataTable's own #cell writes the data-label from the column it is on; this row keeps
      # its own version because it renders outside that component. The index, not the label, so a
      # renamed column changes in one place.
      def cell(index, &block)
        div(class: "data-table-cell", data: { label: COLUMNS[index] }, &block)
      end

      # Reads the loaded association: TournamentsController#show preloads :tournament_entry
      # precisely for this, and a nil viewer is a visitor, who owns nothing.
      def mine? = @viewer.present? && @standing.tournament_entry&.user_id == @viewer.id

      # Linked for a member, plain for a visitor. This sheet is public and /archetypes is not,
      # so a bare `href:` here would hand every visitor a link to a sign-in wall. The viewer is
      # already in hand — TournamentsController#show and StandingListImportJob both pass one —
      # so nothing here has to call a policy to answer it.
      def archetype_badge
        href = archetype_path(@standing.archetype) if @viewer.present?
        render Ui::ArchetypeBadge.new(archetype: @standing.archetype, href: href)
      end

      def list_link
        return plain "—" if @standing.deck.nil?

        link_to "Decklist", deck_path(@standing.deck)
      end

      def actions
        claim_or_unclaim
        return unless @can_edit

        render Ui::AdminActions.new(
          edit_path: edit_tournament_standing_path(@standing.tournament_id, @standing),
          delete_path: tournament_standing_path(@standing.tournament_id, @standing),
          confirm_message: "Delete #{@standing.player_name}'s standing?"
        )
      end

      # Plural on purpose. Entry uniqueness is per Play! Pokémon profile, so a parent tracking
      # their own and their child's profiles legitimately has two participations at one event —
      # every reader of that rule has to be plural, and one button per claimable participation is
      # what stops the second one being unreachable.
      def claim_or_unclaim
        if mine?
          button_to "Unlink", unclaim_tournament_standing_path(@standing.tournament_id, @standing),
            method: :delete, class: "btn btn-secondary btn-sm"
        elsif @standing.tournament_entry_id.nil?
          @claimable_entries.each { |entry| claim_button(entry) }
        end
      end

      def claim_button(entry)
        button_to claim_label(entry),
          claim_tournament_standing_path(@standing.tournament_id, @standing,
            tournament_entry_id: entry.id),
          method: :post, class: "btn btn-secondary btn-sm"
      end

      def claim_label(entry)
        return "This is me" if @claimable_entries.one?

        name = entry.tournament_profile&.player_name
        name ? "This is #{name}" : "This is me (no profile)"
      end
    end
  end
end
