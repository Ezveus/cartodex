require "application_system_test_case"

# The result modal's version question. Its three answers sat side by side like the Save row they
# replace, and "Create version 2" / "Attach to version 1" / "Cancel" do not fit one line of the
# dialog: each squeezed to its longest word and wrapped — three lines at 344px, and still two at
# 1400px, where the dialog keeps its own narrow width. So both ends are pinned: 344 because the
# sweep's mobile half renders at 500 (Chrome's floor), 1400 because the desktop side had it too.
module ResultVersionPromptLayout
  # Sub-pixel layout: a full-width button can measure a fraction short of its row.
  TOLERANCE = 1
  # One line of a .btn label is ~44px; a wrapped one is a multiple of ~20 more.
  MAX_BUTTON_HEIGHT = 48

  def self.included(base)
    base.class_eval do
      setup do
        @user = users(:one)
        login_as @user, scope: :user
        @deck = @user.decks.create!(name: "Honedge Box", physical: true, standard_pool: standard_pools(:twm_por))
        @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
        Decks::VersionSnapshot.call(@deck, effective_at: 2.days.ago)
        @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)
      end

      test "the three answers stack inside the prompt, one full-width, one-line button per row" do
        visit deck_path(@deck)
        click_button "Log Result"
        find(".result-type-btn.result-win").click
        click_button "Save"
        assert_button "Attach to version 1"

        row = rect(find(".result-version-prompt .result-modal-actions"))
        buttons = all(".result-version-prompt .result-modal-actions .btn", count: 3).map { |b| [ b.text, rect(b) ] }

        buttons.each do |label, box|
          assert_operator box["left"], :>=, row["left"] - TOLERANCE, "#{label}: starts left of the prompt"
          assert_operator box["right"], :<=, row["right"] + TOLERANCE, "#{label}: runs past the prompt"
          assert_in_delta row["width"], box["width"], TOLERANCE, "#{label}: not full width"
          assert_operator box["height"], :<=, MAX_BUTTON_HEIGHT, "#{label}: wraps onto several lines"
        end

        buttons.each_cons(2) do |(above_label, above), (below_label, below)|
          assert_operator below["top"], :>=, above["bottom"], "#{below_label} is not below #{above_label}"
        end
      end

      private

      def rect(element)
        page.evaluate_script("JSON.parse(JSON.stringify(arguments[0].getBoundingClientRect()))", element)
      end
    end
  end
end

class ResultVersionPromptNarrowTest < ApplicationSystemTestCase
  drive_at 344, 780
  include ResultVersionPromptLayout
end

class ResultVersionPromptWideTest < ApplicationSystemTestCase
  drive_at 1400, 900
  include ResultVersionPromptLayout
end
