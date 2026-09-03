# Public tournaments — Stage 2: the public opening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `tournaments#index` and `tournaments#show` outside the session gate, so a visitor browses the catalog and reads an event's page, with a rate limit bounding what that costs and no member affordance leaking onto either page.

**Architecture:** `TournamentsController` gains `PubliclyReachable` (which drops the Devise gate for two actions, makes `verify_authorized` mandatory on every action, and routes the two "not for you" exceptions onto one renderer) plus a per-IP rate limit on the catalog. The `rescue_from` written in Stage 1 keeps an unauthorized edit redirecting rather than 404ing, because an event's existence is public. No schema change, no new model, no new policy — Stage 1 wrote the policies precisely so this stage is small.

**Tech Stack:** Rails 8.1, Ruby 3.4.1, Pundit, Devise, `rate_limit` over `RateLimitStore`, Phlex, Capybara/Selenium.

**Spec:** `docs/superpowers/specs/2026-09-03-public-tournaments-design.md`

## Global Constraints

- **Stage 1 must be complete and green before this starts.** This plan modifies files Stage 1 creates.
- **Only `index` and `show` open.** `mine`, `new`, `create`, `edit`, `update`, `destroy` and everything under `Tournaments::EntriesController` stay owner-only. An over-broad `skip_before_action` is exactly the bug `test/controllers/public_access_test.rb` exists to catch, which is why its assertions are per action and not per controller.
- **`Tournaments::EntriesController` does NOT include `PubliclyReachable`.** Its routes ride out of the `authenticate :user` block by nesting alone, exactly as `DeckResultsController`'s do; `authenticate_user!` stays its only gate and it gets no `verify_authorized`. Adding the concern there would be a change nobody asked for.
- **404 stays the answer for an unknown event; a redirect stays the answer for "not yours".** Both are already written; this stage must not let the concern's handler swallow the second.
- **Lint only the files you touched** (`bin/rubocop <files>`): a repo-wide run reports ~159 pre-existing offences CI does not see.

---

### Task 1: Open the two actions

**Files:**
- Modify: `config/routes.rb` (move the `resources :tournaments` block out of `authenticate :user`)
- Modify: `app/controllers/tournaments_controller.rb`
- Modify: `app/services/search/global.rb`
- Modify: `test/controllers/public_access_test.rb`
- Modify: `test/services/search/global_test.rb`

**Interfaces:**
- Consumes: `TournamentPolicy` (already answering `index?`/`show?` unconditionally) and the `rescue_from` from Stage 1.
- Produces: `/tournaments` and `/tournaments/:id` answering without a session; `Search::Global` returning catalog results for a visitor.

- [ ] **Step 1: Write the failing test**

In `test/controllers/public_access_test.rb`, add `tournaments` to the two lists the file already builds. Find the `public_gets` and `owner_only_gets` private methods and add:

```ruby
      [ "tournament catalog", tournaments_path ],
      [ "tournament page", tournament_path(tournaments(:one)) ],
```

to `public_gets`, and:

```ruby
      [ "my tournaments", mine_tournaments_path ],
      [ "new tournament", new_tournament_path ],
      [ "edit tournament", edit_tournament_path(tournaments(:one)) ],
      [ "tournament entry", tournament_entry_path(tournaments(:one), tournament_entries(:one)) ],
      [ "edit tournament entry", edit_tournament_entry_path(tournaments(:one), tournament_entries(:one)) ],
```

to `owner_only_gets`. Note that `edit_tournament_path(tournaments(:one))` is signed-in-safe for the "authorizes when a session is present" test only because `tournaments(:one).created_by` is `users(:one)`, the user that test signs in — if that fixture changes, this row goes with it.

Then add a test of its own for the write side:

```ruby
  test "the tournament writes send a visitor to sign in" do
    name_was = tournaments(:one).name

    post tournaments_path, params: { tournament: { name: "x", date: "2026-05-01" } }
    assert_redirected_to new_user_session_path

    patch tournament_path(tournaments(:one)), params: { tournament: { name: "x" } }
    assert_redirected_to new_user_session_path

    delete tournament_path(tournaments(:one))
    assert_redirected_to new_user_session_path

    post tournament_entries_path(tournaments(:one)), params: { tournament_entry: { deck_id: decks(:one).id } }
    assert_redirected_to new_user_session_path

    assert_equal name_was, tournaments(:one).reload.name
    assert_equal 2, Tournament.count
  end

  # An event's existence is public, so this is the opposite answer from a deck's: not the
  # static 404 that hides whether the record exists, but a real 404 for an id that does not
  # exist — and, for one that does, the redirect Stage 1 wrote.
  test "an unknown tournament answers 404 to a visitor" do
    get tournament_path(id: 999_999)

    assert_response :not_found
  end
```

In `test/services/search/global_test.rb`, replace the Stage 1 test "a visitor gets no tournament results while the catalog still requires a session" with:

```ruby
  test "a visitor's search finds tournaments in the catalog" do
    result = Search::Global.call(user: nil, query: "regional")

    assert_includes result.tournaments, tournaments(:one)
    assert_equal 1, result.tournament_total
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/public_access_test.rb test/services/search/global_test.rb`
Expected: FAIL — the catalog and event page redirect a visitor to sign-in, and the visitor's search group is still empty.

- [ ] **Step 3: Move the routes out of the session gate**

In `config/routes.rb`, cut the whole `resources :tournaments do … end` block out of the `authenticate :user` block and paste it next to `resources :decks` and `resources :cards`, above the `# Authenticated routes` comment. `resources :tournament_profiles` stays inside — it is owner-only in full.

Add above it:

```ruby
  # index and show only; the rest of the resource, and every nested entry route, gates itself
  # through Devise. The entry routes ride out of `authenticate :user` by nesting alone, the
  # same way deck_results do under decks.
```

- [ ] **Step 4: Open the two actions in the controller**

In `app/controllers/tournaments_controller.rb`, add below `include Searchable`:

```ruby
  include PubliclyReachable

  publicly_reachable :index, :show
```

Leave the `rescue_from Pundit::NotAuthorizedError` line **below** the `include`: `rescue_from` handlers are consulted in reverse order of declaration, so the controller's own must be declared after the concern's to win for `NotAuthorizedError`. Add that sentence to the comment already sitting above it if it does not say it yet.

- [ ] **Step 5: Drop the visitor branch from the search scope**

In `app/services/search/global.rb`, replace `tournament_scope` with:

```ruby
    # The catalog is public, so unlike the deck scopes above this one does not depend on who
    # is asking. A participation has no name of its own and is found through its event.
    def tournament_scope
      @tournament_scope ||= Tournament.name_matching(@query)
    end
```

- [ ] **Step 6: Run it to verify it passes**

Run: `bin/rails test test/controllers/public_access_test.rb test/services/search/global_test.rb`
Expected: PASS.

- [ ] **Step 7: Sabotage-check both halves of the boundary**

1. Change `publicly_reachable :index, :show` to `publicly_reachable :index, :show, :mine`. Run `bin/rails test test/controllers/public_access_test.rb`. Expected: "the owner-only actions send a visitor to sign in" FAILS on "my tournaments" — this is the over-broad `skip_before_action` the file exists to catch. Restore.
2. Delete the `rescue_from Pundit::NotAuthorizedError` line. Run `bin/rails test test/controllers/tournaments_controller_test.rb`. Expected: "another member is sent back to the event with an alert instead of a 404" FAILS, now answering the concern's static 404. Restore.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/tournaments_controller.rb app/services/search/global.rb test
git commit -m "Open the tournament catalog and event page to visitors"
```

---

### Task 2: Nothing on either page for a visitor to click

**Files:**
- Modify: `app/views/components/tournaments/show_view.rb`
- Modify: `app/views/tournaments/show.html.erb`
- Modify: `test/controllers/tournaments_controller_test.rb`

**Interfaces:**
- Consumes: `Tournaments::ShowView` from Stage 1 Task 5.
- Produces: `Tournaments::ShowView.new(tournament:, my_entry:, can_edit:, can_record:)`.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/tournaments_controller_test.rb`:

```ruby
  test "a visitor sees the event and no control that would bounce them to sign in" do
    sign_out @user

    get tournament_path(@tournament)

    assert_response :success
    assert_select "h1", text: @tournament.name
    assert_select ".tournament-details", text: /#{@tournament.tier_label}/
    assert_select "a[href=?]", new_tournament_entry_path(@tournament), count: 0
    assert_select "a[href=?]", edit_tournament_path(@tournament), count: 0
  end

  test "a visitor's catalog offers no way to add a tournament" do
    sign_out @user

    get tournaments_path

    assert_response :success
    assert_select ".data-table-row", count: 2
    assert_select "a[href=?]", new_tournament_path, count: 0
    assert_select ".tournament-attended", count: 0
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/tournaments_controller_test.rb`
Expected: FAIL on the first test — `@my_entry` is nil for a visitor, so `entry_action` renders "Record your participation", a link straight to the sign-in page. The catalog test passes already (`can_create` comes from a policy that answers false for a visitor); it is there so a later change cannot quietly break it.

- [ ] **Step 3: Gate the call to action**

In `app/views/components/tournaments/show_view.rb`, take a fourth keyword and use it:

```ruby
    def initialize(tournament:, my_entry: nil, can_edit: false, can_record: false)
      @tournament = tournament
      @my_entry = my_entry
      @can_edit = can_edit
      @can_record = can_record
    end
```

```ruby
    # A visitor gets neither branch. "Record your participation" would be a link to the
    # sign-in page dressed as a primary action, and inviting somebody to sign in is the
    # navbar's job, not this page's.
    def entry_action
      return link_to "Your entry", tournament_entry_path(@tournament, @my_entry), class: "btn btn-primary" if @my_entry
      return unless @can_record

      link_to "Record your participation", new_tournament_entry_path(@tournament), class: "btn btn-primary"
    end
```

In `app/views/tournaments/show.html.erb`:

```erb
<%= render Tournaments::ShowView.new(tournament: @tournament, my_entry: @my_entry,
                                     can_edit: policy(@tournament).edit?,
                                     can_record: policy(Tournament).mine?) %>
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bin/rails test test/controllers/tournaments_controller_test.rb`
Expected: PASS, the Stage 1 tests "show renders the event and offers the reader their own entry" and "show invites a reader with no entry to record one" included — both sign in.

- [ ] **Step 5: Commit**

```bash
git add app/views test/controllers/tournaments_controller_test.rb
git commit -m "Show a visitor the event and nothing they cannot use"
```

---

### Task 3: The rate limit

**Files:**
- Modify: `app/controllers/tournaments_controller.rb`
- Create: `test/controllers/tournaments_rate_limit_test.rb`

**Interfaces:**
- Consumes: `RateLimitStore`, the `with_real_rate_limit_store` test helper.
- Produces: `TournamentsController::CATALOG_RATE_LIMIT_TO`.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/tournaments_rate_limit_test.rb`. It mirrors `test/controllers/decks_rate_limit_test.rb`: the test environment's cache store is `:null_store`, which makes `rate_limit` a no-op, so a real store has to stand in.

```ruby
require "test_helper"

# The catalog left the `authenticate :user` block, and it is the same shape as
# DecksController#shared — a debounced field driving a paginated listing — so it gets the same
# 60/min. The event page gets none: one page load per click, no live control behind it.
class TournamentsRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "throttles an anonymous client past the catalog limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = TournamentsController::CATALOG_RATE_LIMIT_TO

      limit.times do
        get tournaments_path
        assert_response :success
      end

      get tournaments_path
      assert_response :too_many_requests

      # The `unless: -> { user_signed_in? }` guard: a signed-in client must sail past the same
      # limit that just stopped the anonymous one.
      sign_in users(:one)

      (limit + 1).times do
        get tournaments_path
        assert_response :success
      end
    end
  end

  test "an event page is not rationed" do
    with_real_rate_limit_store do
      (TournamentsController::CATALOG_RATE_LIMIT_TO + 5).times do
        get tournament_path(tournaments(:one))
        assert_response :success
      end
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/tournaments_rate_limit_test.rb`
Expected: FAIL with `NameError: uninitialized constant TournamentsController::CATALOG_RATE_LIMIT_TO`.

- [ ] **Step 3: Add the limit**

In `app/controllers/tournaments_controller.rb`, below `CATALOG_PER_PAGE`:

```ruby
  # 60/min, the number DecksController#shared carries, because the catalog is the same shape
  # and the same cost: a field debounced at 300ms driving a paginated listing behind a Turbo
  # Frame, so a keystroke pays the pager's COUNT and one page of rows. #show gets none — one
  # page load per click, with no live control behind it, exactly as decks#show has none.
  CATALOG_RATE_LIMIT_TO = 60
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: CATALOG_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "tournaments-index", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :index
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bin/rails test test/controllers/tournaments_rate_limit_test.rb`
Expected: PASS.

- [ ] **Step 5: Sabotage-check the signed-in exemption**

Remove `unless: -> { user_signed_in? }`. Run the file. Expected: the second half of the first test FAILS — a signed-in client gets a 429. Restore.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/tournaments_controller.rb test/controllers/tournaments_rate_limit_test.rb
git commit -m "Bound what an anonymous catalog search costs"
```

---

### Task 4: The visitor's navbar

**Files:**
- Modify: `app/views/components/ui/public_navbar.rb`
- Modify: `test/controllers/navbar_active_section_test.rb`
- Modify: `test/system/public_navigation_test.rb`

**Interfaces:**
- Consumes: the open routes from Task 1, `Ui::NavLinks::SECTION_OVERRIDES` from Stage 1 Task 7.
- Produces: a "Tournaments" entry on `Ui::PublicNavbar`.

- [ ] **Step 1: Write the failing tests**

In `test/controllers/navbar_active_section_test.rb`:

```ruby
  test "a visitor's tournament pages light the catalog entry" do
    assert_active_nav_link "Tournaments", tournaments_path
    # One section, not two: unlike "Shared decks", this link has no second list to stand in
    # for — a visitor cannot reach /tournaments/mine at all.
    assert_active_nav_link "Tournaments", tournament_path(tournaments(:one))
  end
```

In `test/system/public_navigation_test.rb`:

```ruby
  test "a visitor can reach the catalog from the navbar and open an event" do
    visit cards_path

    # Not a plain click: below the breakpoint the menu is display:none until the hamburger
    # opens it, and this is the assertion that PublicNavbar really carries that hamburger.
    click_nav_link "Tournaments"

    assert_current_path tournaments_path
    click_on tournaments(:one).name

    assert_selector "h1", text: tournaments(:one).name
    # Nothing on the page for somebody who cannot act on it.
    assert_no_link "Record your participation"
    assert_no_link "Edit"
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/controllers/navbar_active_section_test.rb`
Expected: FAIL — a visitor's navbar has no "Tournaments" entry, so no link is lit and `assert_equal [ label ], active` gets `[]`.

- [ ] **Step 3: Add the entry**

In `app/views/components/ui/public_navbar.rb`, inside `.navbar-links`:

```ruby
          nav_link "Tournaments", tournaments_path, "tournaments"
```

Place it after "Cards" and before "Shared decks", so the visitor's order matches the member navbar's.

- [ ] **Step 4: Run the controller test, then both system sides**

Run: `bin/rails test test/controllers/navbar_active_section_test.rb`
Expected: PASS.

Run: `bin/rails test:system test/system/public_navigation_test.rb`
Expected: PASS.

Run: `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system test/system/public_navigation_test.rb`
Expected: PASS. If it fails here and not on the desktop side, the cause is almost always a plain `click_on` on a nav link rather than `click_nav_link`.

- [ ] **Step 5: Commit**

```bash
git add app/views/components/ui/public_navbar.rb test
git commit -m "Give a visitor the tournament catalog in the navbar"
```

---

### Task 5: The documentation and the full check

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Extend the public-surface paragraph**

In the **Controllers** and **Shared decks / `PubliclyReachable`** paragraphs of `CLAUDE.md`, record that `tournaments#index` and `#show` have joined the surface `PubliclyReachable` opens; that `TournamentsController` is the second includer to override the concern's handling, and for the opposite reason to `DecksController`'s — an event's existence is public, so a refused edit redirects with an alert rather than serving the 404 that would hide whether the record exists, while `RecordNotFound` keeps that 404; and that `Tournaments::EntriesController` is a second deliberate exception of the `DeckResultsController` kind: its routes ride out by nesting, it keeps `authenticate_user!` as its only gate, and it gets no `verify_authorized`.

Update the sentence listing the routes outside `authenticate :user` so it names `resources :tournaments` too, and the one listing the `PubliclyReachable` includers.

- [ ] **Step 2: Extend the `RateLimitStore` paragraph**

Record the sixth `rate_limit`: `TournamentsController#index` at 60/min per IP, `unless user_signed_in?`, sized from `decks#shared` because the two endpoints have the same shape and the same cost, and note that `#show` gets none for the same reason `decks#show` does.

- [ ] **Step 3: Run everything CI runs**

```bash
bin/rubocop $(git diff --name-only master...HEAD | grep -E '\.rb$' | tr '\n' ' ')
bin/brakeman --no-pager
bin/importmap audit
bin/rails db:test:prepare test
bin/rails test:system
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system
```

Expected: all clean.

- [ ] **Step 4: Check the public surface by hand once**

Not automatable in a way worth the code, and cheap to do: with `bin/dev` running and a private browser window (no session), visit `/tournaments`, search, page, open an event, and confirm the `x-robots-tag: noindex, nofollow` header is present on both (`curl -sI localhost:3000/tournaments | grep -i robots`). The header comes from `XRobotsTagMiddleware` at position 0 of the stack and needs no work here — this step is only to confirm the new pages did not find a way around it.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the public tournament catalog"
```
