module Tournaments
  # The public face of an event. It shows the event and nothing else: no attendee list, no
  # entry count, no deck anybody played. The only thing it knows about its reader is whether
  # they have a participation of their own to go to.
  class ShowView < ApplicationComponent
    def initialize(tournament:, my_entry: nil, can_edit: false)
      @tournament = tournament
      @my_entry = my_entry
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

    def entry_action
      if @my_entry
        link_to "Your entry", tournament_entry_path(@tournament, @my_entry), class: "btn btn-primary"
      else
        link_to "Record your participation", new_tournament_entry_path(@tournament), class: "btn btn-primary"
      end
    end
  end
end
