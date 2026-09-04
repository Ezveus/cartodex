module Tournaments
  # The public face of an event. It shows the event and nothing else: no attendee list, no
  # entry count, no deck anybody played. The only thing it knows about its reader is whether
  # they have a participation of their own to go to.
  class ShowView < ApplicationComponent
    def initialize(tournament:, my_entries: [], can_record: false,
                   can_record_another: false, can_edit: false)
      @tournament = tournament
      @my_entries = my_entries
      @can_record = can_record
      @can_record_another = can_record_another
      @can_edit = can_edit
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
      end
    end

    private

    # Two rules meet here. A reader has as many participations as they have Play! Pokémon
    # profiles that attended, so this is a list, not a link — and the "record" button survives
    # alongside it, since a second profile has no other route to a form. A visitor gets none of
    # it: `can_record` guards the whole method rather than the `empty?` branch alone, because a
    # visitor's `my_entries` is `[]` by construction, and "Record your participation" would then
    # be a link to the sign-in page dressed as a primary action. Inviting somebody to sign in is
    # the navbar's job, not this page's.
    def entry_action
      return unless @can_record

      if @my_entries.empty?
        link_to "Record your participation", new_tournament_entry_path(@tournament), class: "btn btn-primary"
        return
      end

      @my_entries.each do |entry|
        link_to entry_label(entry), tournament_entry_path(@tournament, entry), class: "btn btn-primary"
      end
      return unless @can_record_another

      link_to "Record another participation", new_tournament_entry_path(@tournament), class: "btn btn-secondary"
    end

    # One participation needs no disambiguation and naming the profile would be noise; two need
    # it, and the player name is the only thing that tells them apart.
    def entry_label(entry)
      return "Your entry" if @my_entries.one?

      player_name = entry.tournament_profile&.player_name
      player_name ? "Your entry (#{player_name})" : "Your entry (no profile)"
    end
  end
end
