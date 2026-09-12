module Decks
  module Odds
    # The combination's current assignment *and* its answer, together, because the two are one state
    # and rendering them in two places is how they come to disagree.
    #
    # Every pick, drop and new group navigates this frame. The alternative — templating the chips in
    # JavaScript and asking only for the number — would put the bucket cap, the disjointness rule and
    # the group names in a second place, and one of the two would drift.
    class ComboFrame < ApplicationComponent
      # ApplicationComponent includes a fixed list of Rails helpers and this is not among them —
      # Decks::ShareFrame includes it by hand for the same reason.
      include Phlex::Rails::Helpers::TurboFrameTag
      include Formatting

      FRAME_ID = "deck_odds_combo".freeze

      def initialize(report:, combo:)
        @report = report
        @combo = combo
      end

      def view_template
        # The frame target sits on the <turbo-frame> itself, which is what the controller navigates
        # by writing `src`. Turbo replaces the element's children and leaves the element alone, so
        # this attribute survives every load — and so does the target binding.
        turbo_frame_tag(FRAME_ID, data: { deck_combo_target: "frame" }) do
          # The controller reads the assignment back off this element rather than holding it, so a
          # frame load is the only thing that has to be right for the next click to be.
          div(data: { deck_combo_target: "state", assignment: serialized })

          groups.each_with_index { |bucket, index| group(bucket, index) }

          div(class: "odds-combo-actions") do
            button(type: "button", class: "btn btn-secondary btn-sm",
                   disabled: groups.size >= Combo::MAX_BUCKETS,
                   data: { action: "deck-combo#addBucket" }) { "New group" }
          end

          answer
        end
      end

      private

      # One empty group when nothing has been asked, so there is something to add a card to. Also the
      # state a refusal lands in: Combo drops the buckets rather than echoing a half-parsed
      # assignment back.
      def groups = @combo.buckets.presence || [ [] ]

      def serialized
        groups.map { |bucket| bucket.map(&:key).join(Combo::CARD_SEPARATOR) }
              .join(Combo::BUCKET_SEPARATOR)
      end

      def group(bucket, index)
        div(class: "odds-combo-group") do
          div(class: "odds-combo-group-head") do
            span(class: "odds-combo-group-title") { "Group #{index + 1}" }
            if groups.size > 1
              button(type: "button", class: "btn btn-secondary btn-sm",
                     aria_label: "Remove group #{index + 1}",
                     data: { action: "deck-combo#removeBucket",
                             deck_combo_index_param: index }) { "×" }
            end
          end

          div(class: "odds-combo-chips") { bucket.each { |entry| chip(entry, index) } }

          button(type: "button", class: "btn btn-secondary btn-sm",
                 data: { deck_combo_target: "addCard",
                         action: "deck-combo#openPicker",
                         deck_combo_index_param: index }) { "Add a card" }
        end
      end

      def chip(entry, index)
        span(class: "odds-combo-chip") do
          plain "#{entry.name} (#{entry.copies})"
          button(type: "button", class: "odds-combo-chip-drop", aria_label: "Remove #{entry.name}",
                 data: { action: "deck-combo#drop",
                         deck_combo_index_param: index,
                         deck_combo_key_param: entry.key }) { "×" }
        end
      end

      def answer
        if @combo.error
          p(class: "odds-combo-error") { @combo.error }
        elsif @combo.answered?
          p(class: "odds-combo-answer") do
            plain "At least one from every group: "
            render Cell.new(curve: @combo.curve, index: @report.default_seen)
          end
        end
      end
    end
  end
end
