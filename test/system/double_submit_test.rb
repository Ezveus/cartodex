require "application_system_test_case"

# Both writes that a second click can duplicate before the first has answered.
# The clicks are dispatched from JS, back to back in one script, because that is
# the interleaving at stake: the handler runs synchronously up to its first
# `await`, so the guard it sets is in place before the second click is
# dispatched — and a disabled button swallows that click rather than raising the
# way Capybara's own `click` would.
class DoubleSubmitTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
    @deck = @user.decks.create!(name: "Froakie Box", physical: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:froakie_twm), quantity: 4)
  end

  # Nothing identifies two logged results as a duplicate — two matches with the
  # same score on the same day is an ordinary evening — so a second POST is a
  # second row, and no server-side idempotence can take it back.
  test "a double-clicked Save logs one result" do
    visit deck_path(@deck)
    click_button "Log Result"
    find(".result-type-btn.result-win").click

    double_click("[data-result-modal-target='submitButton']")

    assert_no_selector "dialog.result-modal[open]"
    assert_equal 1, @deck.deck_results.count
  end

  # The archetype endpoint *is* idempotent on the fingerprint pair, so the row is
  # not what this protects — the assertion is on the request. What the guard buys
  # is that the click is acknowledged at all: nothing else on screen changes
  # until the answer comes back.
  test "a double-clicked Create & select sends one request" do
    visit edit_deck_path(@deck)
    click_button "Suggest"
    assert_field(with: "Froakie (TWM 56)")

    count_posts_to("/api/archetypes")
    double_click("[data-archetype-picker-target='createButton']")

    assert_no_selector ".create-archetype-section", visible: true
    assert_equal 1, evaluate_script("window.__posts")
    assert_equal 1, Archetype.where(primary_card: cards(:froakie_twm)).count
  end

  private

  def double_click(selector)
    execute_script(<<~JS)
      const button = document.querySelector("#{selector}")
      button.click()
      button.click()
    JS
  end

  def count_posts_to(path)
    execute_script(<<~JS)
      window.__posts = 0
      const original = window.fetch
      window.fetch = (url, options = {}) => {
        if (options.method === "POST" && String(url).includes("#{path}")) window.__posts += 1
        return original(url, options)
      }
    JS
  end
end
