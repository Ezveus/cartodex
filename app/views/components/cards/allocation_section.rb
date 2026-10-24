module Cards
  # The reader's own copies of this exact printing: owned, committed to physical decks, available,
  # and which decks commit them. A frame, because the "In collection" counter above it writes
  # without reloading the page and card_allocation_controller.js reloads this from the server on
  # each change — a printing can be several collection rows (language, finish), so the client
  # cannot recompute owned from the counter alone.
  class AllocationSection < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "card-allocation".freeze

    # `decks` is Allocations::PhysicalDecksByCard's list for this card, already ordered by name.
    def initialize(card:, allocation:, decks:)
      @card = card
      @allocation = allocation
      @decks = decks
    end

    def view_template
      # `_top`: the deck links and the report link leave the card page rather than load into here.
      turbo_frame_tag(
        FRAME_ID,
        target: "_top",
        data: {
          controller: "card-allocation",
          card_allocation_url_value: card_path(@card),
          action: "collection-quantity:changed@window->card-allocation#refresh"
        }
      ) do
        div(class: "card-info-section card-allocation") do
          h2 { "Your copies" }
          dl(class: "card-info-list") do
            stat("Owned", @allocation.owned)
            stat("Committed", @allocation.committed)
            stat("Available", @allocation.available)
          end
          over_allocation_note
          decks_list
        end
      end
    end

    private

    def stat(label, value)
      div(class: "card-allocation-stat") do
        dt { label }
        dd { value.to_s }
      end
    end

    # `available` is clamped at zero, so without this a member whose decks count copies they no
    # longer own would read "0 available" and nothing else.
    def over_allocation_note
      excess = @allocation.committed - @allocation.owned
      return unless excess.positive?

      p(class: "card-allocation-over over-allocation-banner badge-warning") do
        plain "Your decks commit #{excess} more #{'copy'.pluralize(excess)} than you own. "
        link_to "Review over-allocations", over_allocations_path
      end
    end

    def decks_list
      if @decks.empty?
        p(class: "card-allocation-empty") { "No physical deck uses a real copy of this printing." }
        return
      end

      ul(class: "card-allocation-decks") do
        @decks.each do |deck|
          li(class: "card-allocation-deck") do
            link_to deck[:name], deck_path(deck[:key])
            span(class: "card-allocation-deck-count") { copies(deck[:owned_copies]) }
          end
        end
      end
    end

    def copies(count)
      "#{count} #{'copy'.pluralize(count)}"
    end
  end
end
