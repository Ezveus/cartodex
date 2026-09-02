# Shared Decks — Stage 2: a deck can be shared, and three surfaces stop requiring a session

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deck can be shared; a shared deck shows its decklist and its exports to anybody with the link; the card catalog and the dashboard work without a session; and search gains a fourth group for other people's shared decks.

**Architecture:** `decks.shared` is a boolean with hand-written `shared`/`unshared` scopes (Active Record refuses a `public` or `private` scope). Pundit holds the rules; a `PubliclyReachable` concern makes "this controller can be reached without a session", "every action must authorize", and "both not-found exceptions render the same 404" inseparable. `DecksController#show` branches **once** on ownership into either today's `Decks::ShowView` or a new read-only `Decks::PublicShowView` — a separate file, so it cannot leak an owner control it does not contain.

**Tech Stack:** Ruby 3.4.1, Rails 8.1, SQLite, Minitest with parallel execution, Phlex views, Hotwire, Devise, Pundit (new), the `mcp` gem.

**Spec:** `docs/superpowers/specs/2026-09-02-shared-decks-design.md` — read all of it, and "Authorization" twice.

**Depends on:** `docs/superpowers/plans/2026-09-02-shared-decks-stage-1-identity.md`, complete and merged. Every URL below is a key.

## Global Constraints

- **All views are Phlex components.** Never write ERB view logic. See the `phlex-architecture` skill.
- **Code and code comments in English.**
- `bin/rubocop`, `bin/rails test`, `bin/brakeman --no-pager` must pass before every commit.
- System tests must pass at **both** viewports: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`. Never click a nav link directly — use `click_nav_link`.
- **A task that touches routes, a layout, a navbar, or a `before_action` runs both system suites before committing.** Tasks 4, 6 and 7 all move the ground the whole suite stands on.
- **Sabotage-verify every new test.** This matters more here than anywhere: Task 3's leak test is a list of `count: 0` assertions, and an absence test that has never been red proves nothing.
- **`current_user` can be `nil` in any policy.** `ApplicationPolicy` must not raise on an absent user; a policy that rejects one makes every public page impossible.
- **No policy grants admin anything.** `Admin::BaseController#require_admin!` stays the admin gate, and `Admin::DecksController` keeps its own unscoped lookups. A `user.admin?` clause in `DeckPolicy` would let an admin open any private deck at its normal URL.
- **Only one unscoped `Deck.find_by!(key:)` is created in this whole stage**, in `DecksController`'s publicly reachable actions, immediately followed by `authorize`. Every other lookup keeps `current_user.decks`.
- Nothing in the app is indexable (decision 12). Do not add a `Disallow` to `robots.txt` — Task 6 explains why that would defeat it.

---

## Task 1: `decks.shared`, and duplicating never publishes

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_shared_to_decks.rb`
- Modify: `app/models/deck.rb`, `db/schema.rb`
- Test: `test/models/deck_test.rb`

**Interfaces:**
- Produces: `Deck#shared?`, `Deck.shared`, `Deck.unshared`.

**Context you need:** `enum :visibility, { private: …, public: … }` will not load — `ActiveRecord::Base.dangerous_class_method?` is `true` for both `:public` and `:private`, so the scopes the enum generates are refused. Hence a boolean plus hand-written scopes. The names `shared`/`unshared` also match the "Share" verb the UI uses.

- [ ] **Step 1: Write the failing tests**

```ruby
  test "a deck is private until it is shared" do
    deck = users(:one).decks.create!(name: "Fresh", standard_pool: standard_pools(:twm_por))

    refute_predicate deck, :shared?
    assert_includes Deck.unshared, deck
    refute_includes Deck.shared, deck
  end

  test "duplicating a shared deck produces a private copy" do
    source = decks(:one)
    source.update!(shared: true)

    copy = Decks::Duplicator.call(source)

    # Duplicator copies an explicit attribute allowlist, so `shared` is excluded by
    # construction. The test guards the next person who reaches for `dup` instead.
    refute_predicate copy, :shared?
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bin/rails test test/models/deck_test.rb -n "/shared/"`
Expected: FAIL — unknown attribute `shared`.

- [ ] **Step 3: Write the migration**

```ruby
class AddSharedToDecks < ActiveRecord::Migration[8.1]
  def change
    add_column :decks, :shared, :boolean, null: false, default: false

    # [:shared, :created_at] rather than a partial index on `shared` alone: two of the
    # three readers order by created_at (the dashboard showcase and the paginated
    # /decks/shared), and an index on a single-valued boolean only enumerates rows — it
    # does not serve a sort. The third reader is a LIKE, which stays a scan regardless.
    add_index :decks, [ :shared, :created_at ]
  end
end
```

- [ ] **Step 4: Add the scopes**

In `app/models/deck.rb`, beside `with_proxies`:

```ruby
  # Written by hand, not generated: Active Record refuses to define a scope named `public`
  # or `private`, since both are Module methods. `shared`/`unshared` is also the vocabulary
  # the Share modal and the badge use, so the column, the scopes and the UI agree.
  scope :shared, -> { where(shared: true) }
  scope :unshared, -> { where(shared: false) }
```

- [ ] **Step 5: Migrate, run, sabotage**

Run: `bin/rails db:migrate && bin/rails db:test:prepare && bin/rails test test/models/deck_test.rb`
Expected: PASS.

Add `shared: @deck.shared` to `Decks::Duplicator`'s `create!` and re-run: the duplication test must FAIL. Restore.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/deck.rb test/models/deck_test.rb
git commit -m "Give a deck a shared flag, private by default

A boolean and hand-written scopes rather than an enum: Active Record
refuses to define a scope named public or private. Indexed as
[shared, created_at] because both listing readers order by date, and an
index on a single-valued boolean serves no sort."
```

---

## Task 2: Pundit, and the policies

Policies only — no controller calls `authorize` yet. This task is fully unit-testable and its review seat is "are the rules right", separate from "is the boundary wired correctly".

**Files:**
- Modify: `Gemfile`, `Gemfile.lock`
- Modify: `app/controllers/application_controller.rb`
- Create: `app/policies/application_policy.rb`, `app/policies/deck_policy.rb`, `app/policies/card_policy.rb`, `app/policies/dashboard_policy.rb`
- Test: `test/policies/deck_policy_test.rb`

**Interfaces:**
- Produces: `DeckPolicy.new(user_or_nil, deck)` answering `show?`, `export?`, `tournament_pdf?`, `stats?`, `results?`, `update?`, `destroy?`, `duplicate?`, `share?`, `create?`, `shared_index?`; `DeckPolicy::Scope.new(user_or_nil, Deck).resolve`. `CardPolicy` and `DashboardPolicy` answer `true` to their queries.

- [ ] **Step 1: Write the failing policy tests**

Create `test/policies/deck_policy_test.rb`:

```ruby
require "test_helper"

class DeckPolicyTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @stranger = users(:two)
    @deck = decks(:one)
    @deck.update!(user: @owner, shared: false)
  end

  test "an owner may do everything to their own deck" do
    policy = DeckPolicy.new(@owner, @deck)

    %i[show? export? tournament_pdf? stats? results? update? destroy? duplicate? share?].each do |query|
      assert policy.public_send(query), "expected the owner to be allowed #{query}"
    end
  end

  test "nobody but the owner may see a private deck" do
    refute DeckPolicy.new(@stranger, @deck).show?
    refute DeckPolicy.new(nil, @deck).show?
  end

  test "anybody may see and export a shared deck" do
    @deck.update!(shared: true)

    [ @stranger, nil ].each do |viewer|
      policy = DeckPolicy.new(viewer, @deck)
      assert policy.show?, "expected #{viewer.inspect} to be allowed show?"
      assert policy.export?, "expected #{viewer.inspect} to be allowed export?"
    end
  end

  test "sharing a deck exposes neither its record nor its writes" do
    @deck.update!(shared: true)

    [ @stranger, nil ].each do |viewer|
      policy = DeckPolicy.new(viewer, @deck)
      %i[tournament_pdf? stats? results? update? destroy? duplicate? share?].each do |query|
        refute policy.public_send(query), "expected #{viewer.inspect} to be refused #{query}"
      end
    end
  end

  test "an admin gets no special access to a private deck" do
    admin = users(:two)
    admin.update!(admin: true)

    # Deliberately no admin clause: Admin::BaseController is the admin gate, and an admin
    # opening any private deck at its normal URL is well beyond what an admin panel needs.
    refute DeckPolicy.new(admin, @deck).show?
  end

  test "creating a deck needs a session" do
    assert DeckPolicy.new(@owner, Deck).create?
    refute DeckPolicy.new(nil, Deck).create?
  end

  test "the shared index is open to everyone" do
    assert DeckPolicy.new(nil, Deck).shared_index?
  end

  test "the scope is mine plus everybody's shared, or just the shared ones" do
    mine_private = @deck
    theirs_shared = decks(:two)
    theirs_shared.update!(user: @stranger, shared: true)

    signed_in = DeckPolicy::Scope.new(@owner, Deck).resolve
    assert_includes signed_in, mine_private
    assert_includes signed_in, theirs_shared

    visitor = DeckPolicy::Scope.new(nil, Deck).resolve
    refute_includes visitor, mine_private
    assert_includes visitor, theirs_shared
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/policies/deck_policy_test.rb`
Expected: FAIL — `NameError: uninitialized constant DeckPolicy`.

- [ ] **Step 3: Add the gem**

In `Gemfile`, next to `gem "devise"`:

```ruby
gem "pundit"
```

Run: `bundle install`

- [ ] **Step 4: Write `ApplicationPolicy`**

Create `app/policies/application_policy.rb`:

```ruby
# Base policy. Written by hand rather than generated, for one reason: Pundit's generator
# template has been known to `raise` on a nil user, and in this app `current_user` is nil on
# every public page. A policy that rejects an absent user makes the whole public surface
# impossible, so `user` is simply allowed to be nil and each query says what it means.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?  = false
  def show?   = false
  def create? = false
  def new?    = create?
  def update? = false
  def edit?   = update?
  def destroy? = false

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class} must implement #resolve"
    end
  end
end
```

- [ ] **Step 5: Write `DeckPolicy`**

Create `app/policies/deck_policy.rb`:

```ruby
class DeckPolicy < ApplicationPolicy
  # A shared deck shows its decklist and its exports to anybody. Everything else about it —
  # the win/loss record, the tournament PDF (which reads one of the owner's profiles), every
  # write — stays with the owner.
  def show?   = owner? || record.shared?
  def export? = show?

  def tournament_pdf? = owner?
  def stats?          = owner?
  def results?        = owner?

  def update?    = owner?
  def edit?      = owner?
  def destroy?   = owner?
  def duplicate? = owner?
  def share?     = owner?

  def index?  = user.present?
  def create? = user.present?

  # The index of shared decks is the same page for a visitor and a member.
  def shared_index? = true

  class Scope < ApplicationPolicy::Scope
    # "The decks I may see." Not what either listing page uses — /decks is the owner's own
    # and /decks/shared is Deck.shared — but what a search across both has to ask.
    def resolve
      user ? scope.where(user: user).or(scope.shared) : scope.shared
    end
  end

  private

  # nil user included: a visitor owns nothing.
  def owner? = user.present? && record.user_id == user.id
end
```

- [ ] **Step 6: Write the two "yes to everyone" policies**

Create `app/policies/card_policy.rb`:

```ruby
# The card catalog is public. A policy that says "yes, to everyone" is not ceremony here: it
# is the written trace of that decision, and it is what stops verify_authorized from having a
# blind spot over the cards controller.
class CardPolicy < ApplicationPolicy
  def index? = true
  def show?  = true
  def image? = true
end
```

Create `app/policies/dashboard_policy.rb`:

```ruby
# Headless policy — the dashboard has no record. `authorize :dashboard, :show?` routes here.
class DashboardPolicy < ApplicationPolicy
  def show? = true
end
```

- [ ] **Step 7: Include Pundit**

In `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  protect_from_forgery with: :exception
  before_action :authenticate_user!
  layout -> { Layouts::ApplicationLayout }
end
```

`pundit_user` is left at its default, which is `current_user` — and which is allowed to be nil.

- [ ] **Step 8: Run the tests and sabotage**

Run: `bin/rails test test/policies/`
Expected: PASS.

Change `show?` to `owner? || true` and re-run: the private-deck test must FAIL. Restore. Then add `|| user&.admin?` to `show?` and re-run: the admin test must FAIL. Restore.

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock app/policies app/controllers/application_controller.rb test/policies
git commit -m "Put the sharing rules in Pundit policies, nil user included

ApplicationPolicy is hand-written so it never raises on an absent user:
current_user is nil on every public page, and a policy that refuses one
makes the public surface impossible. No policy grants an admin anything —
Admin::BaseController stays the admin gate, and an admin opening a private
deck at its normal URL is not what an admin panel is for."
```

---

## Task 3: the public deck view, and the single branch that chooses it

Still inside the `authenticate` block. That is deliberate: the public branch is fully exercisable by a **signed-in non-owner**, so the leak test can be written and made red before any route opens. Task 4 opens the routes afterwards, as its own reviewable step.

**Files:**
- Create: `app/views/components/ui/archetype_badge.rb`
- Create: `app/views/components/decks/public_badges.rb`
- Create: `app/views/components/decks/public_deck_card_item.rb`
- Create: `app/views/components/decks/public_show_view.rb`
- Create: `app/views/decks/public_show.html.erb`
- Modify: `app/views/components/decks/classification_badges.rb`
- Modify: `app/controllers/decks_controller.rb` (`#show`, `#export`)
- Test: `test/controllers/decks_controller_test.rb`

**Interfaces:**
- Consumes: `DeckPolicy` (Task 2), `Deck.shared` (Task 1).
- Produces: `Ui::ArchetypeBadge.new(archetype:)`; `Decks::PublicBadges.new(deck:)`; `Decks::PublicDeckCardItem.new(deck_card:)`; `Decks::PublicShowView.new(deck:)`.

**Context you need — the DOM contract the image export reads.** `deck_image_export_controller.js` queries `.deck-card-item`, reads `dataset.cardPreviewUrl` and `.deck-card-qty` inside each, and names the download from `.deck-show-header h1`. Exports are in the public scope (decision 3), so the public row and header **must** keep those four hooks or the export silently produces an empty image.

- [ ] **Step 1: Write the failing leak test**

In `test/controllers/decks_controller_test.rb`:

```ruby
  test "a signed-in stranger sees a shared deck's decklist and none of its owner controls" do
    @deck.update!(shared: true)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 0)
    sign_in users(:two)

    get deck_path(@deck)

    assert_response :success
    assert_select "h1", text: @deck.name
    assert_select ".deck-card-item", count: 1

    # The DOM contract the image export depends on — the export is public, so these are
    # requirements, not incidental markup.
    assert_select ".deck-show-header h1"
    assert_select ".deck-card-item[data-card-preview-url]"
    assert_select ".deck-card-item .deck-card-qty"

    # Absence assertions: the whole point of a separate view is that it cannot render these.
    assert_select ".deck-card-alloc", count: 0
    assert_select ".deck-card-set-swap", count: 0
    assert_select ".deck-badges .badge", text: "Proxies", count: 0
    assert_select "a[href=?]", edit_deck_path(@deck), count: 0
    assert_select "button", text: "Log Result", count: 0
    assert_select ".deck-card-search", count: 0
  end

  test "a signed-in stranger cannot see an unshared deck" do
    sign_in users(:two)

    get deck_path(@deck)

    assert_response :not_found
  end

  test "a stranger may export a shared deck but not its tournament pdf" do
    @deck.update!(shared: true)
    sign_in users(:two)

    get export_deck_path(@deck)
    assert_response :success

    get export_deck_path(@deck, style: "tournament_pdf", profile_id: 1)
    assert_response :not_found
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bin/rails test test/controllers/decks_controller_test.rb -n "/stranger/"`
Expected: FAIL — currently `current_user.decks.find_by!` raises for a stranger, so all three are 404 (the first two for the wrong reason, the third half by accident).

- [ ] **Step 3: Extract the archetype badge**

Create `app/views/components/ui/archetype_badge.rb` by moving `Decks::ClassificationBadges#archetype_badge` verbatim, comment included:

```ruby
module Ui
  # An archetype as a badge, tinted by its lead card's energy type with a colour pip. Falls
  # back to the neutral archetype style when the type is unknown — which is always true of a
  # Trainer lead, since it has no energy type.
  #
  # Extracted from Decks::ClassificationBadges so the public badge row can reuse it: the two
  # rows show different things, but an archetype looks the same on both.
  class ArchetypeBadge < ApplicationComponent
    def initialize(archetype:)
      @archetype = archetype
    end

    def view_template
      slug = @archetype.primary_energy_type&.downcase

      if slug
        span(class: "badge badge-energy badge-#{slug}") do
          span(class: "badge-pip")
          plain @archetype.name
        end
      else
        span(class: "badge badge-archetype") { @archetype.name }
      end
    end
  end
end
```

In `app/views/components/decks/classification_badges.rb`, delete the private `archetype_badge` method and call the component instead:

```ruby
        render Ui::ArchetypeBadge.new(archetype: @deck.archetype) if @deck.archetype
```

- [ ] **Step 4: Write the public badge row**

Create `app/views/components/decks/public_badges.rb`:

```ruby
module Decks
  # The badges a visitor may see: the format and the archetype, and nothing else.
  #
  # Deliberately not ClassificationBadges with a flag. "Physical" and "TCG Live" say how the
  # owner plays the deck and are of no use to a reader; "Proxies" and "To review" report what
  # the owner does and does not own, which is collection data reached through a deck.
  class PublicBadges < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      div(class: "deck-badges") do
        span(class: "badge badge-format") { @deck.format_label }
        render Ui::ArchetypeBadge.new(archetype: @deck.archetype) if @deck.archetype
      end
    end
  end
end
```

- [ ] **Step 5: Write the public card row**

Create `app/views/components/decks/public_deck_card_item.rb`:

```ruby
module Decks
  # A deck card, read-only. No quantity stepper, no printing picker, no allocation controls —
  # this component contains none of them, which is what makes the public page unable to leak
  # one.
  #
  # The class name, the preview URL and the `.deck-card-qty` element are not decoration:
  # deck_image_export_controller.js reads all three, and the image export is part of what a
  # shared deck offers.
  class PublicDeckCardItem < ApplicationComponent
    def initialize(deck_card:)
      @deck_card = deck_card
    end

    def view_template
      li(
        class: "deck-card-item",
        data: {
          card_preview_url: card.image_url.present? ? image_card_path(card) : nil,
          card_preview_card_id: card.id,
          action: "mouseenter->card-preview#show click->card-preview#open"
        }
      ) do
        div(class: "deck-card-qty-controls") do
          span(class: "deck-card-qty") { @deck_card.quantity.to_s }
        end
        span(class: "deck-card-name") { card.name }
        span(class: "deck-card-set") { "#{card.set_name} #{card.set_number}" }
      end
    end

    private

    def card = @deck_card.card
  end
end
```

- [ ] **Step 6: Write the public page**

Create `app/views/components/decks/public_show_view.rb`:

```ruby
module Decks
  # A shared deck, as anybody but its owner sees it: the decklist and the exports.
  #
  # A separate file rather than a flag on Decks::ShowView, which carries ten owner-only
  # affordances (inline editing, card search, result logging, allocation steppers, printing
  # pickers, the tournament PDF, the actions dropdown…). Guarding each of them would put ten
  # conditions in the app's largest component, and one forgotten condition is a collection
  # leak to a stranger. This view cannot leak what it does not contain.
  class PublicShowView < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      div(class: "deck-show-container", data: { controller: "card-preview" }) do
        header_section
        stats_section
        div(class: "deck-show-content") do
          main_section
          preview_section
        end
      end
    end

    private

    # `.deck-show-header h1` is what the image export names the file from.
    def header_section
      div(class: "deck-show-header") do
        div do
          h1 { @deck.name }
          render Decks::PublicBadges.new(deck: @deck)
          p(class: "deck-show-description") { @deck.description } if @deck.description.present?
        end
      end
      nav(class: "deck-actions-bar") { export_dropdown }
    end

    # No tournament PDF: it reads one of the owner's tournament profiles.
    def export_dropdown
      div(class: "dropdown", data: { controller: "dropdown" }) do
        button(class: "btn btn-secondary btn-sm", data: { action: "dropdown#toggle" }) { "Export ▾" }
        div(class: "dropdown-menu", data: { dropdown_target: "menu" }) do
          button(
            class: "dropdown-item",
            data: { controller: "clipboard", clipboard_url_value: export_deck_path(@deck), action: "clipboard#copy" }
          ) { "Copy for TCG Live" }
          button(
            class: "dropdown-item",
            data: { controller: "clipboard", clipboard_url_value: export_deck_path(@deck, style: "cardmarket"), action: "clipboard#copy" }
          ) { "Copy as Cardmarket wishlist" }
          button(
            class: "dropdown-item",
            data: { controller: "deck-image-export", action: "deck-image-export#copy" }
          ) { "Copy as image" }
          button(
            class: "dropdown-item",
            data: { controller: "deck-image-export", action: "deck-image-export#download" }
          ) { "Download as image" }
        end
      end
    end

    # The card count only. No wins, losses, draws or timeouts: the record stays private.
    def stats_section
      div(class: "deck-show-stats") do
        render Ui::Stat.new(value: @deck.deck_cards.sum(&:quantity), label: "cards")
      end
    end

    def main_section
      div(class: "deck-show-main") do
        groups = @deck.deck_cards.group_by { |deck_card| deck_card.card.card_type }

        [ "Pokémon", "Trainer", "Energy" ].each do |type|
          group = groups[type]
          next if group.blank?

          h3(class: "deck-card-group-title") { "#{type} (#{group.sum(&:quantity)})" }
          ul(class: "deck-card-list") do
            group.each { |deck_card| render Decks::PublicDeckCardItem.new(deck_card: deck_card) }
          end
        end
      end
    end

    # Copied verbatim from Decks::ShowView, targets included. Above the 768px breakpoint the
    # hover pane is what fills; below it, card_preview_controller.js checks
    # window.innerWidth <= 768 and uses the <dialog> instead — so both halves have to be here
    # or the mobile side of the preview silently does nothing.
    def preview_section
      div(class: "deck-show-preview") do
        image_tag "", data: { card_preview_target: "image" }, class: "card-preview-image", style: "display: none"
        link_to "View card details", "#", data: { card_preview_target: "link" }, class: "card-preview-link", style: "display: none"
      end
      card_preview_modal
    end

    def card_preview_modal
      dialog(
        class: "card-preview-modal",
        data: {
          card_preview_target: "modal",
          action: "click->card-preview#backdropClose"
        }
      ) do
        div(class: "card-preview-modal-content") do
          image_tag "", data: { card_preview_target: "modalImage" }, class: "card-preview-modal-image"
          link_to "View card details", "#", data: { card_preview_target: "modalLink" }, class: "btn btn-secondary btn-sm"
          button(class: "btn btn-sm", data: { action: "card-preview#closeModal" }) { "Close" }
        end
      end
    end
  end
end
```

Create `app/views/decks/public_show.html.erb`:

```erb
<%= render Decks::PublicShowView.new(deck: @deck) %>
```

- [ ] **Step 7: Branch once in the controller**

In `app/controllers/decks_controller.rb#show`:

```ruby
  def show
    # The only unscoped deck lookup in the app that this feature creates. `authorize` is the
    # next line for that reason, and nothing else loads until it has run.
    @deck = Deck.find_by!(key: params[:id])
    authorize @deck

    if @deck.user_id == current_user&.id
      owner_show
    else
      public_show
    end
  end
```

and, private:

```ruby
  # `includes` cannot be chained onto a `find_by!`, so each branch reloads with the preloads
  # it needs. The alternative was to load the owner's preloads up front, which would make a
  # visitor's request load deck_results and tournaments — exactly what the public view exists
  # to avoid. One extra query is the price of authorizing before loading anything else.
  def owner_show
    @deck = current_user.decks.includes(:archetype, :tournaments, deck_cards: :card, deck_results: []).find(@deck.id)
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
    @editing = false
    @swappable_card_ids = Cards::Printings.swappable_card_ids(@deck.deck_cards.map(&:card))

    if @deck.physical?
      @availability = Allocations::Availability.for_cards(
        user: current_user, cards: @deck.deck_cards.map(&:card), excluding_deck: @deck
      )
      @over_allocated_card_ids = Allocations::OverAllocations.call(user: current_user).map { |o| o[:card_id] }.to_set
    else
      @availability = {}
      @over_allocated_card_ids = Set.new
    end

    render :show
  end

  def public_show
    @deck = Deck.includes(deck_cards: :card).find(@deck.id)
    # Devise only remembers a location when authenticate_user! bounces a request, so without
    # this a visitor who clicks Sign in here lands on the dashboard and has to find the deck
    # again.
    store_location_for(:user, request.fullpath)
    render :public_show
  end
```

In `#export`, authorize before touching anything:

```ruby
  def export
    @deck = Deck.find_by!(key: params[:id])
    authorize @deck, :export?

    deck = Deck.includes(deck_cards: { card: [ :attacks, :abilities ] }).find(@deck.id)

    case params[:style]
    when "tournament_pdf"
      # Reads one of the owner's profiles, so it is a stricter question than :export?.
      authorize @deck, :tournament_pdf?
      profile = current_user.tournament_profiles.find(params[:profile_id])
      # …unchanged from here
```

**Order matters:** without `authorize @deck, :tournament_pdf?` *before* `current_user.tournament_profiles`, a visitor hits `NoMethodError` on nil rather than a 404.

- [ ] **Step 8: Make `NotAuthorizedError` a 404, temporarily, in this controller**

`PubliclyReachable` lands in Task 4 and will own this. Until then, so this task's tests can pass, add to `DecksController`:

```ruby
  # Moves into PubliclyReachable in the next task, which is where the reasoning lives.
  rescue_from Pundit::NotAuthorizedError, with: :not_found

  private

  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
```

- [ ] **Step 9: Run the tests, then sabotage the leak test**

Run: `bin/rails test test/controllers/decks_controller_test.rb`
Expected: PASS.

Now make `public_show` `render :show` instead. Re-run: the leak test **must** fail on several of the `count: 0` assertions. If it passes, the absence assertions are matching the wrong selectors and prove nothing — fix them before restoring.

- [ ] **Step 10: Both system suites, then commit**

Run: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`
Expected: PASS — `#show` changed shape for the owner too.

```bash
git add app/views app/controllers/decks_controller.rb test/controllers/decks_controller_test.rb
git commit -m "Show a shared deck to a stranger, through a view that has no owner controls

A separate component rather than a flag on Decks::ShowView: that view
carries ten owner-only affordances, and one forgotten guard is a
collection leak. This one cannot leak what it does not contain, which is
why the test is a list of absence assertions — sabotage-verified by
rendering ShowView instead.

Still inside the authenticate block. The public branch is exercised by a
signed-in non-owner, so opening the routes stays a separate step."
```

---

## Task 4: `PubliclyReachable`, and the routes leave the session gate

**Files:**
- Create: `app/controllers/concerns/publicly_reachable.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/home_controller.rb`, `search_controller.rb`, `decks_controller.rb`, `cards_controller.rb`, `deck_results_controller.rb`
- Modify: `app/views/components/cards/show_view.rb`, `app/views/cards/show.html.erb`
- Test: `test/controllers/decks_controller_test.rb`, `cards_controller_test.rb`, `home_controller_test.rb`, `search_controller_test.rb`, `test/controllers/public_access_test.rb` (new)

**Interfaces:**
- Produces: `PubliclyReachable` with the class method `publicly_reachable(*actions)`.

**Context you need — two traps, both measured:**

1. `HomeController#dashboard` calls `authenticate_user!` **in its own body** (`home_controller.rb:9`), on top of the app-wide `before_action`. A `skip_before_action` does not touch a call inside a method. Leave it and the visitor dashboard redirects to sign-in with no visible cause.
2. **A halting `before_action` skips the `after_action` too.** So on a signed-out request to an owner-only action, `authenticate_user!` redirects and `verify_authorized` never runs — a missing `authorize` on `edit`/`update`/`destroy`/`duplicate`/`stats` is invisible to a signed-out test. Hence a signed-in request per action as well.

Also: `resources :decks` has `deck_results` nested inside it, so those routes leave the block too. `DeckResultsController` does **not** include the concern — it keeps `authenticate_user!` as its only gate and calls `authorize @deck, :results?` by hand.

- [ ] **Step 1: Write the failing access tests**

Create `test/controllers/public_access_test.rb`:

```ruby
require "test_helper"

# The routes for decks, cards, the dashboard and search left the `authenticate :user` block,
# so each of those actions lost one of its two guards. This file is what replaces it: one
# assertion per action, signed out, plus one per action signed in — because a halting
# before_action skips the after_action, so verify_authorized cannot fire on the signed-out
# half at all.
class PublicAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user)
    @card = cards(:honedge)
  end

  PUBLIC_GETS = ->(t) {
    {
      "dashboard" => t.dashboard_path,
      "search" => t.search_path(q: "ab"),
      "cards index" => t.cards_path,
      "card show" => t.card_path(t.instance_variable_get(:@card)),
      "deck show (shared)" => t.deck_path(t.instance_variable_get(:@deck))
    }
  }

  OWNER_ONLY_GETS = ->(t) {
    deck = t.instance_variable_get(:@deck)
    {
      "decks index" => t.decks_path,
      "deck new" => t.new_deck_path,
      "deck edit" => t.edit_deck_path(deck),
      "deck stats" => t.stats_deck_path(deck),
      "deck matchups" => t.matchups_decks_path,
      "deck results" => t.deck_deck_results_path(deck),
      "collections" => t.collections_path
    }
  }

  test "the public actions answer without a session" do
    @deck.update!(shared: true)

    PUBLIC_GETS.call(self).each do |label, path|
      get path
      assert_response :success, "expected #{label} to be public, got #{response.status}"
    end
  end

  test "the owner-only actions send a visitor to sign in" do
    OWNER_ONLY_GETS.call(self).each do |label, path|
      get path
      assert_redirected_to new_user_session_path, "expected #{label} to require a session"
    end
  end

  test "every owner-only action authorizes when a session is present" do
    sign_in @user

    # This is the half that can actually catch a missing `authorize`: verify_authorized runs
    # as an after_action, and an after_action does not run when a before_action halted.
    OWNER_ONLY_GETS.call(self).each do |label, path|
      get path
      assert_response :success, "expected #{label} to answer for its owner, got #{response.status}"
    end
  end

  test "an unknown key, a private deck and a stranger are indistinguishable" do
    sign_in users(:two)
    private_deck = @deck

    get deck_path(private_deck)
    private_body = response.body
    private_status = response.status

    get "/decks/thiskeydoesnotexist22"
    unknown_body = response.body
    unknown_status = response.status

    assert_equal 404, private_status
    assert_equal 404, unknown_status
    # Bodies, not just statuses: the two reach the renderer through different exceptions
    # (Pundit::NotAuthorizedError and ActiveRecord::RecordNotFound), and only rescuing both
    # in one place makes them converge. A 403 on one of them would turn an unguessable key
    # into an existence oracle for private decks.
    assert_equal private_body, unknown_body
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/public_access_test.rb`
Expected: FAIL — every public GET redirects to sign-in.

- [ ] **Step 3: Write the concern**

Create `app/controllers/concerns/publicly_reachable.rb`:

```ruby
# A controller reachable without a session. The three things it does must never be separated:
# it drops the app-wide Devise gate for the actions it names, it makes Pundit's
# verify_authorized mandatory on *every* action of the controller, and it routes both
# "not for you" exceptions onto one renderer so that an unknown key and a private record are
# indistinguishable.
#
# Note what verify_authorized cannot do: a before_action that halts the chain skips the
# after_action too, so on a signed-out request to an owner-only action authenticate_user!
# redirects and this check never runs. It catches a missing `authorize` only on requests that
# reach the action. test/controllers/public_access_test.rb covers the other half by making the
# same requests signed in.
module PubliclyReachable
  extend ActiveSupport::Concern

  included do
    after_action :verify_authorized
    rescue_from ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, with: :not_found
  end

  class_methods do
    def publicly_reachable(*actions)
      skip_before_action :authenticate_user!, only: actions
    end
  end

  private

  # The same static page the rest of the app serves. Not an in-app 404 with a navbar:
  # /tournaments/999 would keep serving this file, and a deck answering differently from
  # everything else is a difference nobody asked for.
  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
```

- [ ] **Step 4: Move the four route entries out of the block**

In `config/routes.rb`, lift `get "dashboard"`, `get "search"`, `resources :decks` (with its whole block, `deck_results` included) and `resources :cards` **above** `authenticate :user do`, with a comment:

```ruby
  # Outside `authenticate :user`: these controllers straddle the session boundary and gate
  # themselves through PubliclyReachable. Note that `resources :decks` carries its nested
  # deck_results routes out with it — DeckResultsController deliberately does not include the
  # concern and keeps ApplicationController's before_action as its only gate.
  get "dashboard", to: "home#dashboard"
  get "search", to: "search#show"

  resources :decks, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    # …unchanged block
  end

  resources :cards, only: [ :index, :show ] do
    get :image, on: :member
  end
```

Everything else stays inside the block.

- [ ] **Step 5: Gate each controller**

`DecksController` — replace the temporary `rescue_from` from Task 3 with the concern, and authorize every action:

```ruby
class DecksController < ApplicationController
  include Searchable
  include PubliclyReachable

  publicly_reachable :show, :export, :shared
```

Record actions authorize the record; record-less ones authorize the class, because `verify_authorized` covers every action of this controller:

```ruby
  def index
    authorize Deck, :index?
    # …
  end

  def new
    @deck = Deck.new
    authorize @deck
  end

  def create
    @deck = current_user.decks.build(deck_params)
    authorize @deck
    # …
  end

  def matchups
    authorize Deck, :index?
    # …
  end

  def compare
    authorize Deck, :index?
    # …
  end
```

and each of `edit`, `update`, `destroy`, `duplicate`, `stats` adds `authorize @deck` (or `authorize deck`) after its scoped `find_by!`.

`CardsController`:

```ruby
class CardsController < ApplicationController
  include CardSearchable
  include PubliclyReachable

  publicly_reachable :index, :show, :image
```

with `authorize Card, :index?` in `#index`, `authorize @card` in `#show`, `authorize card, :image?` in `#image`, and the collection quantity made nil-safe:

```ruby
    @collection_quantity = current_user&.collections&.find_by(card_id: @card.id)&.quantity.to_i
```

`HomeController` — and **delete the `authenticate_user!` line from the body**:

```ruby
class HomeController < ApplicationController
  include PubliclyReachable

  publicly_reachable :dashboard

  def dashboard
    authorize :dashboard, :show?
    @pending_deck_imports = current_user ? current_user.imports.deck_imports.pending : []
  end
end
```

`#welcome` and its route are removed in Task 11, not here; until then keep the action and give it `publicly_reachable :welcome, :dashboard` plus `authorize :dashboard, :show?` in `#welcome` too.

`SearchController`:

```ruby
class SearchController < ApplicationController
  include Searchable
  include PubliclyReachable

  publicly_reachable :show

  layout false

  def show
    authorize :dashboard, :show?
    @results = search_results
  end
end
```

`Searchable#search_results` already passes `user: current_user`, and a nil user would reach `@user.decks` and raise. So the nil guard lands **here**, not in Task 10 — `/search` becomes public in this task, and an action that 500s for every visitor is not "publicly reachable". In `app/services/search/global.rb`:

```ruby
    # A nil user is a visitor: nothing personal is searched, and nothing personal is queried
    # either — Deck.none and Tournament.none never touch the database.
    def deck_scope
      @deck_scope ||= @user ? @user.decks.search(@query) : Deck.none
    end

    def tournament_scope
      @tournament_scope ||= @user ? @user.tournaments.name_matching(@query) : Tournament.none
    end
```

Task 10 adds the fourth group on top of these; it does not revisit them.

`DeckResultsController` — no concern, one added authorize:

```ruby
    @deck = current_user.decks.find_by!(key: params[:deck_id])
    authorize @deck, :results?
```

- [ ] **Step 6: Hide the collection control from visitors**

`app/views/components/cards/show_view.rb`:

```ruby
    def initialize(card:, alt_printings:, collection_quantity: 0, signed_in: false)
      # …
      @signed_in = signed_in
    end
```

and where it renders:

```ruby
            collection_control if @signed_in
```

`app/views/cards/show.html.erb`:

```erb
<%= render Cards::ShowView.new(card: @card, alt_printings: @alt_printings, collection_quantity: @collection_quantity, signed_in: user_signed_in?) %>
```

- [ ] **Step 7: Run the access tests, then sabotage twice**

Run: `bin/rails test test/controllers/public_access_test.rb`
Expected: PASS. (`deck show (shared)` needs the deck shared — the first test does that.)

Sabotage 1: add `:index` to `DecksController`'s `publicly_reachable` list. The "sends a visitor to sign in" test must FAIL.
Sabotage 2: remove `authorize Deck, :index?` from `#index`. The "authorizes when a session is present" test must FAIL with `Pundit::AuthorizationNotPerformedError`. If it passes, `verify_authorized` is not installed — check the concern is actually included.
Restore both.

- [ ] **Step 8: Run everything, both viewports, then commit**

Run: `bin/rails test && bin/rubocop && bin/brakeman --no-pager`
Then: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`

```bash
git add app/controllers config/routes.rb app/views/cards app/views/components/cards test/controllers
git commit -m "Let four route entries out of the session gate, with the concern that holds them

PubliclyReachable ties three things that must not drift apart: dropping
the Devise gate per action, requiring authorize on every action, and
rendering one 404 for both a private record and an unknown key — a 403 on
either would turn an unguessable key into an existence oracle.

Two measured traps. #dashboard called authenticate_user! inside its own
body, which no skip_before_action reaches. And a halting before_action
skips the after_action, so verify_authorized cannot see a missing
authorize on a signed-out request — hence a signed-in assertion per
action as well."
```

---

## Task 5: pay for what just opened

**Files:**
- Create: `app/lib/rate_limit_store.rb`
- Modify: `app/controllers/mcp/server_controller.rb`, `app/controllers/oauth/registrations_controller.rb`
- Modify: `app/controllers/cards_controller.rb`, `app/controllers/search_controller.rb`
- Modify: `app/views/components/cards/index_view.rb`, `app/views/cards/index.html.erb`
- Test: `test/controllers/cards_controller_test.rb`

**Interfaces:**
- Produces: `RateLimitStore` (top-level, `app/lib` is autoloaded). `Cards::IndexView.new(…, card_counts:)` — a `{ card_set_id => Integer }` hash.

**Context you need:** `RATE_LIMIT_STORE` is copy-pasted verbatim in two controllers. It cannot move to `ApplicationController`: `Mcp::ServerController` inherits `ActionController::API`. And `/cards` currently instantiates the whole catalog — `CardSet.by_release.includes(:cards)` — only so the sidebar can print `card_set.cards.size` (`cards/index_view.rb:93`), plus two unindexed full scans for `@rarities` and `@marks`.

- [ ] **Step 1: Write the failing query-count test**

```ruby
  test "the cards index does not instantiate the catalog to count it" do
    get cards_path # warm the session and the caches

    assert_no_difference -> { Card.count } do
      # The guard is on rows instantiated, not queries: the sidebar needs a count per set,
      # and includes(:cards) built every Card object in the database to get it.
      records = 0
      subscriber = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
        records += payload[:record_count] if payload[:class_name] == "Card"
      end
      get cards_path
      ActiveSupport::Notifications.unsubscribe(subscriber)

      assert_equal 0, records, "the index instantiated #{records} Card objects without a search"
    end
    assert_response :success
  end

  test "the sidebar still shows a card count per set" do
    get cards_path

    assert_response :success
    assert_select ".set-code", text: /\(\d+\)/
  end
```

- [ ] **Step 2: Run and watch the first fail**

Run: `bin/rails test test/controllers/cards_controller_test.rb -n "/catalog to count/"`
Expected: FAIL — a non-zero number of `Card` instantiations.

- [ ] **Step 3: Extract the rate-limit store**

Create `app/lib/rate_limit_store.rb`:

```ruby
# Proxies to Rails.cache at call time (rather than capturing it once at class-load, as the
# `rate_limit` macro's `cache_store` default would), so tests can swap Rails.cache for a real
# store and exercise throttling.
#
# A top-level constant in app/lib rather than a constant on ApplicationController, because
# Mcp::ServerController inherits from ActionController::API and could not reach it there.
module RateLimitStore
  def self.increment(...)
    Rails.cache.increment(...)
  end
end
```

Delete the `RATE_LIMIT_STORE = Module.new do … end` block from `Mcp::ServerController` and `Oauth::RegistrationsController`, and point their `store:` at `RateLimitStore`.

- [ ] **Step 4: Count instead of instantiating**

In `app/controllers/cards_controller.rb#index`:

```ruby
    @blocks = CardSet.by_release.group_by(&:block_name)
    # A count per set, not every Card in the database. The sidebar prints these numbers and
    # nothing else on the page reads the cards themselves.
    @card_counts = Card.group(:card_set_id).count

    # Both lists change only when a set is imported, and neither `rarity` nor
    # `regulation_mark` is indexed — two full scans of `cards` on every request, anonymous
    # ones included, once this action is public. A cache is the honest fix here: an index on a
    # low-cardinality column read on every page load is not.
    cache_key = [ "cards/filter-values", Card.maximum(:updated_at)&.to_i ]
    @rarities, @marks = Rails.cache.fetch(cache_key) do
      [
        Card.where.not(rarity: [ nil, "" ]).distinct.order(:rarity).pluck(:rarity),
        Card.where.not(regulation_mark: [ nil, "" ]).distinct.order(:regulation_mark).pluck(:regulation_mark)
      ]
    end
```

`Cards::IndexView` takes `card_counts:` and its sidebar reads `@card_counts.fetch(card_set.id, 0)` in place of `card_set.cards.size`. Update `app/views/cards/index.html.erb` to pass it.

- [ ] **Step 5: Add the three limiters**

In `app/controllers/cards_controller.rb`:

```ruby
  # The proxy fetches from limitlesstcg.com on every request — #image caches no bytes, so
  # expires_in is a response header and nothing more. Absent a shared cache in front, one
  # inbound request is one outbound request to a third party.
  #
  # 300/min is derived, not copied. The proxy serves exactly two things, the deck page's hover
  # preview and the image export (/cards and /cards/:id hotlink card.image_url directly), and
  # the export loads every printing of a deck in parallel. A deck holds at most 60 cards, so
  # one export is at most 60 requests: 300/min leaves five exports a minute per IP. Copying
  # Mcp::ServerController's 30/min would have broken the second export of the minute — an
  # export the public scope explicitly promises.
  IMAGE_RATE_LIMIT_TO = 300
  INDEX_RATE_LIMIT_TO = 60
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: IMAGE_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "cards-image", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :image

  rate_limit to: INDEX_RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "cards-index", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :index
```

and in `app/controllers/search_controller.rb`:

```ruby
  # One LIKE '%…%' over the whole card catalog per keystroke, plus one over the shared decks.
  # MIN_QUERY_LENGTH and NameNormalizable::MAX_QUERY_LENGTH bound the pattern; nothing bounded
  # the rate until this action became reachable without a session.
  RATE_LIMIT_TO = 120
  RATE_LIMIT_WITHIN = 1.minute

  rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "search", unless: -> { user_signed_in? },
    store: RateLimitStore, only: :show
```

Also flip the image cache header in `#image`:

```ruby
    # Not a secret, and a shared cache in front of the app is the only thing that can make
    # this endpoint cheap.
    expires_in 30.days, public: true
```

- [ ] **Step 6: Run, sabotage, commit**

Run: `bin/rails test test/controllers/ test/mcp/ test/controllers/oauth/`
Expected: PASS, the existing MCP and registration throttling tests included — they exercise `RateLimitStore` through its new home.

Sabotage: restore `includes(:cards)`. The instantiation test must FAIL. Restore.

```bash
git add app/lib app/controllers app/views/components/cards app/views/cards test/controllers
git commit -m "Make the three newly public endpoints affordable, then ration them

/cards instantiated every Card in the database to print a count per set,
and scanned cards twice more for two unindexed filter lists. Rationing an
endpoint that does that would ration an amplifier rather than remove one,
so the queries go first.

The image proxy keeps a limiter at 300/min because it caches no bytes:
one request in is one request out to limitlesstcg. The number comes from
the burst the public scope promises — one image export is at most 60
requests — not from another controller's budget."
```

---

## Task 6: nothing is indexable

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/views/components/layouts/application_layout.rb`
- Modify: `public/robots.txt`
- Test: `test/controllers/public_access_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  test "no response invites indexing, and robots.txt does not block the directive" do
    @deck.update!(shared: true)

    get deck_path(@deck)
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "meta[name=robots][content=?]", "noindex, nofollow"

    # The header covers what has no <head> at all: JSON and the image proxy.
    get cards_path
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]

    # And robots.txt must NOT disallow: a path a crawler may not fetch is a path whose
    # noindex it never reads, and a URL linked from elsewhere can still surface as a bare
    # result. Blocking the crawl defeats the de-indexing it looks like it reinforces.
    refute_match(/^Disallow:\s*\/\s*$/, Rails.public_path.join("robots.txt").read)
  end
```

- [ ] **Step 2: Run and watch it fail**

Run: `bin/rails test test/controllers/public_access_test.rb -n "/indexing/"`
Expected: FAIL — no header, no meta.

- [ ] **Step 3: Send the header everywhere**

In `app/controllers/application_controller.rb`:

```ruby
  before_action :discourage_indexing

  private

  # Nothing in the app is indexable for now (decision 12 of the design). A header rather than
  # only a meta tag because it also covers what has no <head>: the JSON API and the image
  # proxy. Un-sharing a deck takes it off Cartodex at once and would not take it out of a
  # search engine for weeks, and /cards would publish a scraped catalog with its prices.
  def discourage_indexing
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
```

- [ ] **Step 4: Add the meta tag**

In `app/views/components/layouts/application_layout.rb`, beside the viewport meta:

```ruby
          meta(name: "robots", content: "noindex, nofollow")
```

- [ ] **Step 5: Explain robots.txt rather than change it**

Replace the contents of `public/robots.txt`:

```
# See https://www.robotstxt.org/robotstxt.html for documentation on how to use the robots.txt file
#
# Deliberately does NOT disallow anything. Nothing in this app is meant to appear in a search
# engine, and the way to achieve that is the `X-Robots-Tag: noindex, nofollow` header every
# response carries (ApplicationController#discourage_indexing) plus the matching meta tag.
#
# A `Disallow: /` here would defeat it: a path a crawler may not fetch is a path whose noindex
# it never reads, and a URL somebody linked from elsewhere can still surface as a bare result.
# To have nothing indexed you must let the crawler in and hand it the directive.
```

- [ ] **Step 6: Run both suites and commit**

Run: `bin/rails test` then both system suites.

```bash
git add app/controllers/application_controller.rb app/views/components/layouts/application_layout.rb public/robots.txt test/controllers/public_access_test.rb
git commit -m "Keep the whole app out of search engines, without blocking the crawl

X-Robots-Tag on every response plus the meta tag; robots.txt deliberately
left permissive, with a comment saying why. A disallowed path is never
fetched, so its noindex is never read — blocking the crawl defeats the
de-indexing it appears to reinforce."
```

---

## Task 7: `/decks/shared`

Before the navbar, because the navbar links here.

**Files:**
- Modify: `config/routes.rb`, `app/controllers/decks_controller.rb`
- Modify: `app/views/components/decks/deck_card.rb`
- Create: `app/views/components/decks/shared_index_view.rb`, `app/views/decks/shared.html.erb`
- Test: `test/controllers/decks_controller_test.rb`

**Interfaces:**
- Consumes: `Deck.shared` (Task 1), `DeckPolicy#shared_index?` (Task 2), `Decks::PublicBadges` (Task 3).
- Produces: `shared_decks_path`; `Decks::SharedIndexView.new(decks:, filters:, archetype_options:, page:, pages:)`; `Decks::DeckCard.new(deck:, with_actions:, over_allocated:, public_badges:)`.

**Context you need:** routes declared inside a `resources` block are drawn before the member routes — the app already relies on that for `matchups` and `compare` — so `/decks/shared` cannot be swallowed by `/decks/:id`. A 22-character key makes it doubly impossible. There is no pagination gem; follow `CardsController`'s hand-rolled `PER_PAGE` / `offset` / `@pages`.

`Decks::DeckCard` already accepts `with_actions:`, so the shared index reuses it for the row. What it does *not* have is a way to swap its badge row: it renders `Decks::ClassificationBadges`, which shows Physical, TCG Live, Proxies and Shared. On a public surface that must be `Decks::PublicBadges`, so the component gains one more keyword. Its title selector is `.deck-item-link h2`.

- [ ] **Step 1: Write the failing tests**

```ruby
  test "the shared index lists other people's shared decks to a visitor" do
    theirs = decks(:two)
    theirs.update!(user: users(:two), shared: true, name: "Theirs")

    get shared_decks_path

    assert_response :success
    assert_select ".deck-item-link h2", text: "Theirs"
    assert_select "a[href=?]", deck_path(@deck), count: 0
  end

  test "the shared index shows no collection-derived filter and no badge that leaks one" do
    theirs = decks(:two)
    theirs.update!(user: users(:two), shared: true, physical: true)
    theirs.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 0)

    get shared_decks_path

    assert_response :success
    assert_select "select[name=proxies]", count: 0
    assert_select "select[name=support]", count: 0
    assert_select ".deck-badges .badge", text: "Proxies", count: 0
    assert_select ".deck-badges .badge", text: "Physical", count: 0
    assert_select ".deck-item-actions", count: 0
  end

  test "the shared index's archetype filter comes from the shared decks, not from mine" do
    theirs = decks(:two)
    theirs.update!(user: users(:two), shared: true, archetype: archetypes(:one))
    sign_in @user

    get shared_decks_path

    assert_response :success
    assert_select "select[name=primary] option[value=?]", archetypes(:one).primary_card_id.to_s
  end
```

- [ ] **Step 2: Run and watch them fail**

Run: `bin/rails test test/controllers/decks_controller_test.rb -n "/shared index/"`
Expected: FAIL — `undefined method 'shared_decks_path'`.

- [ ] **Step 3: Add the route**

Inside the `resources :decks` block, with the other collection routes:

```ruby
    get :shared, on: :collection
```

- [ ] **Step 4: Add the action**

```ruby
  SHARED_PER_PAGE = 24

  def shared
    authorize Deck, :shared_index?

    scope = Deck.shared.order(created_at: :desc)
    scope = scope.merge(Deck.search(search_query)) if search_query.present?
    scope = scope.where(format: params[:format]) if Deck.formats.key?(params[:format])
    scope = scope.joins(:archetype).where(archetypes: { primary_card_id: params[:primary] }) if params[:primary].present?

    @page = [ params[:page].to_i, 1 ].max
    @pages = (scope.count / SHARED_PER_PAGE.to_f).ceil
    # Same preloads as the dashboard showcase: each row renders the format badge, which names
    # the Standard pool from both of its bounds — three extra queries per Standard deck, times
    # 24 rows, without this.
    @decks = scope.offset((@page - 1) * SHARED_PER_PAGE).limit(SHARED_PER_PAGE)
                  .includes(:deck_cards,
                            archetype: [ :primary_card, :secondary_card ],
                            standard_pool: [ :first_card_set, :last_card_set ])

    @archetype_options = shared_archetype_options
    @filters = { q: search_query.presence, format: params[:format].presence, primary: params[:primary].presence }
  end
```

and, private:

```ruby
  # Derived from the shared decks, deliberately not from member_card_filter_options, which
  # starts at current_user.decks — it would offer a visitor a filter built from nobody's decks
  # and a member one that hides most of the page.
  def shared_archetype_options
    archetype_ids = Deck.shared.where.not(archetype_id: nil).select(:archetype_id)
    card_ids = Archetype.where(id: archetype_ids).select(:primary_card_id)
    Card.where(id: card_ids).order(:name).pluck(:name, :id)
  end
```

- [ ] **Step 5: Let the deck row take a public badge set**

In `app/views/components/decks/deck_card.rb`:

```ruby
    def initialize(deck:, with_actions: true, over_allocated: false, public_badges: false)
      @deck = deck
      @with_actions = with_actions
      @over_allocated = over_allocated
      @public_badges = public_badges
    end
```

and where the badges render:

```ruby
          # Physical, TCG Live, Proxies and Shared all describe how the owner keeps the deck;
          # the first three of those read the collection through it. A public listing gets the
          # format and the archetype only.
          if @public_badges
            render Decks::PublicBadges.new(deck: @deck)
          else
            render Decks::ClassificationBadges.new(deck: @deck, over_allocated: @over_allocated)
          end
```

- [ ] **Step 6: Write the view**

Create `app/views/components/decks/shared_index_view.rb`:

```ruby
module Decks
  # The public listing of shared decks. Same rows as the owner's index, minus everything that
  # compares a deck against a collection the reader does not have: no support or proxies
  # filter, no over-allocation marker, no actions dropdown, no compare bar, no import panel.
  class SharedIndexView < ApplicationComponent
    FORMAT_OPTIONS = [ [ "All formats", "" ] ].freeze

    def initialize(decks:, filters:, archetype_options:, page:, pages:)
      @decks = decks
      @filters = filters
      @archetype_options = archetype_options
      @page = page
      @pages = pages
    end

    def view_template
      div(class: "decks-container") do
        h1 { "Shared decks" }
        filter_bar
        if @decks.any?
          div(class: "deck-list") do
            @decks.each { |deck| render Decks::DeckCard.new(deck: deck, with_actions: false, public_badges: true) }
          end
          pagination if @pages > 1
        else
          p(class: "empty-state") { "No shared decks yet." }
        end
      end
    end

    private

    def filter_bar
      form(action: shared_decks_path, method: "get", class: "deck-filters", data: { controller: "card-filter" }) do
        input(
          type: "search", name: "q", value: @filters[:q], placeholder: "Search shared decks…",
          class: "form-input", autocomplete: "off"
        )
        filter_select(:format, FORMAT_OPTIONS + Deck::FORMAT_LABELS.map { |value, label| [ label, value ] })
        filter_select(:primary, [ [ "Any archetype card", "" ] ] + @archetype_options) if @archetype_options.any?
      end
    end

    def filter_select(name, options)
      selected = @filters[name].to_s
      select(name: name, class: "form-input deck-filter-select", data: { action: "change->card-filter#submit" }) do
        options.each do |label, value|
          if value.to_s == selected
            option(value: value, selected: true) { label }
          else
            option(value: value) { label }
          end
        end
      end
    end

    def pagination
      nav(class: "pagination") do
        link_to "Previous", shared_decks_path(**@filters.compact, page: @page - 1), class: "btn btn-secondary btn-sm" if @page > 1
        span(class: "pagination-position") { "Page #{@page} of #{@pages}" }
        link_to "Next", shared_decks_path(**@filters.compact, page: @page + 1), class: "btn btn-secondary btn-sm" if @page < @pages
      end
    end
  end
end
```

Read `Decks::IndexView#filter_select` before writing this and copy its exact shape if it has drifted — the two should look the same to a user.

Create `app/views/decks/shared.html.erb`:

```erb
<%= render Decks::SharedIndexView.new(
  decks: @decks, filters: @filters, archetype_options: @archetype_options, page: @page, pages: @pages
) %>
```

- [ ] **Step 7: Run, sabotage, commit**

Run: `bin/rails test test/controllers/decks_controller_test.rb`
Expected: PASS.

Sabotage 1: point `shared_archetype_options` at `member_card_filter_options(:primary_card_id)`. The archetype-filter test must FAIL.
Sabotage 2: pass `public_badges: false` in the view. The "no badge that leaks one" test must FAIL on the Physical badge.
Restore both.

```bash
git add config/routes.rb app/controllers/decks_controller.rb app/views test/controllers
git commit -m "Add the shared deck index, with filters that mean something without a collection

No support or proxies filter and no Physical or Proxies badge: all of them
compare a deck against a collection the reader does not have, and the last
two report what the owner does and does not own. Decks::DeckCard takes a
public_badges keyword rather than being duplicated.

The archetype options come from Deck.shared rather than from the viewer's
own decks, which for a visitor would have been a filter derived from
nothing."
```

---

## Task 8: a navbar for visitors, and one link members were missing

**Files:**
- Create: `app/views/components/ui/navbar_shell.rb`, `app/views/components/ui/public_navbar.rb`
- Modify: `app/views/components/ui/app_navbar.rb`, `app/views/components/layouts/application_layout.rb`
- Test: `test/system/public_navigation_test.rb` (new)

**Context you need:** below 768px `.navbar-menu` is `display: none` until the `navbar` Stimulus controller adds `.navbar-menu--open`, and the suite's `click_nav_link` helper depends on exactly those two classes plus `.navbar-toggle`. A `PublicNavbar` that reimplemented "brand plus links" without the hamburger would fail every mobile system test that navigates from a public page, and the failure would read as a Capybara visibility problem.

`shared_decks_path` comes from Task 7, which is why that task runs first.

- [ ] **Step 1: Write the failing system test**

Create `test/system/public_navigation_test.rb`:

```ruby
require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "a visitor can navigate from a shared deck" do
    deck = decks(:one)
    deck.update!(shared: true)

    visit deck_path(deck)
    assert_text deck.name

    # Not a plain click: below the breakpoint the menu is display:none until the hamburger
    # opens it, and this is the assertion that PublicNavbar really carries that hamburger.
    click_nav_link "Cards"

    assert_current_path cards_path
  end

  test "a signed-in user can reach the shared deck index from the navbar" do
    login_as users(:one), scope: :user

    visit dashboard_path
    click_nav_link "Shared decks"

    assert_current_path shared_decks_path
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test:system test/system/public_navigation_test.rb`
Expected: FAIL — no navbar is rendered for a visitor, so `click_nav_link` finds nothing.

- [ ] **Step 3: Extract the shell**

Create `app/views/components/ui/navbar_shell.rb`, moving the chrome out of `Ui::AppNavbar` verbatim:

```ruby
module Ui
  # The navbar's chrome, shared by the signed-in and public variants. Extracted rather than
  # duplicated because it is load-bearing for the test suite, not just for looks: below 768px
  # `.navbar-menu` is display:none until the `navbar` controller adds `.navbar-menu--open`,
  # and `click_nav_link` drives exactly that. A variant missing the toggle fails every mobile
  # system test that navigates, and looks like a Capybara visibility bug.
  class NavbarShell < ApplicationComponent
    def initialize(brand_path:)
      @brand_path = brand_path
    end

    def view_template(&block)
      nav(class: "navbar", data: { controller: "navbar" }) do
        div(class: "navbar-inner") do
          link_to "Cartodex", @brand_path, class: "navbar-brand"
          button(
            class: "navbar-toggle",
            data: { action: "navbar#toggle" },
            aria: { label: "Menu", expanded: "false" }
          ) { span(class: "navbar-toggle-icon") }
          div(class: "navbar-menu", data: { navbar_target: "menu" }, &block)
        end
      end
    end
  end
end
```

`Ui::AppNavbar#view_template` becomes:

```ruby
    def view_template
      render Ui::NavbarShell.new(brand_path: dashboard_path) do
        nav_links
        right_section
      end
    end
```

and `nav_links` gains, after "Decks":

```ruby
        # A member had no way to reach the shared index other than typing a matching search
        # query — the visitor navigated the app better than the member. Both entries light up
        # on /decks/shared, whose controller_name is "decks"; accepted rather than threading a
        # finer activation key through for one row.
        nav_link "Shared decks", shared_decks_path, "decks"
```

Delete `brand` and `hamburger_button` from `AppNavbar`.

- [ ] **Step 4: Write the public navbar**

Create `app/views/components/ui/public_navbar.rb`:

```ruby
module Ui
  # The navbar a visitor gets. Same chrome as Ui::AppNavbar, different links.
  class PublicNavbar < ApplicationComponent
    def initialize(active_controller:)
      @active_controller = active_controller
    end

    def view_template
      render Ui::NavbarShell.new(brand_path: root_path) do
        div(class: "navbar-links") do
          nav_link "Cards", cards_path, "cards"
          nav_link "Shared decks", shared_decks_path, "decks"
        end
        div(class: "navbar-right") do
          link_to "Sign in", new_user_session_path, class: "navbar-link"
          link_to "Sign up", new_user_registration_path, class: "navbar-link"
        end
      end
    end

    private

    def nav_link(label, path, controller)
      link_to label, path, class: [ "navbar-link", ("active" if @active_controller == controller) ].compact.join(" ")
    end
  end
end
```

- [ ] **Step 5: Branch in the layout**

In `app/views/components/layouts/application_layout.rb`:

```ruby
          if user_signed_in?
            turbo_stream_from(current_user, :notifications)
            render Ui::AppNavbar.new(current_user: current_user, active_controller: controller_name)
          else
            render Ui::PublicNavbar.new(active_controller: controller_name)
          end
```

- [ ] **Step 6: Run both system suites, sabotage, commit**

Run: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`
Expected: PASS. `navbar_navigation_test.rb` still passes — the shell is byte-identical for signed-in users.

Sabotage: drop the `button.navbar-toggle` from `NavbarShell`. The mobile run of `public_navigation_test.rb` must FAIL while the desktop run passes — which is exactly the class of bug this extraction prevents.

```bash
git add app/views/components/ui app/views/components/layouts/application_layout.rb test/system/public_navigation_test.rb
git commit -m "Give visitors a navbar, and members the link they were missing

The chrome is extracted rather than duplicated because it is load-bearing
for the suite: below 768px the menu is hidden until the hamburger opens
it, and click_nav_link drives exactly that. A public navbar without the
toggle passes on desktop and fails every mobile navigation test."
```

---

## Task 9: the Share control

**Files:**
- Create: `app/views/components/decks/share_modal.rb`, `app/views/decks/share.turbo_stream.erb`
- Modify: `config/routes.rb`, `app/controllers/decks_controller.rb`
- Modify: `app/views/components/decks/actions_dropdown.rb`, `classification_badges.rb`, `show_view.rb`
- Test: `test/controllers/decks_controller_test.rb`, `test/system/deck_sharing_test.rb` (new)

**Interfaces:**
- Produces: `PATCH /decks/:key/share` → `share_deck_path(deck)`; `Decks::ShareModal.new(deck:)`.

- [ ] **Step 1: Write the failing tests**

In `test/controllers/decks_controller_test.rb`:

```ruby
  test "sharing a deck flips the flag and re-renders the modal with the link" do
    patch share_deck_path(@deck), params: { shared: "1" }, as: :turbo_stream

    assert_response :success
    assert_predicate @deck.reload, :shared?
    assert_match deck_url(@deck), response.body
  end

  test "unsharing takes the deck off the shared index without changing its key" do
    @deck.update!(shared: true)
    key = @deck.key

    patch share_deck_path(@deck), params: { shared: "0" }, as: :turbo_stream

    assert_response :success
    refute_predicate @deck.reload, :shared?
    assert_equal key, @deck.key
  end

  test "a stranger cannot share somebody else's deck" do
    sign_in users(:two)

    patch share_deck_path(@deck), params: { shared: "1" }, as: :turbo_stream

    assert_response :not_found
    refute_predicate @deck.reload, :shared?
  end
```

Create `test/system/deck_sharing_test.rb`:

```ruby
require "application_system_test_case"

class DeckSharingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, shared: false)
    login_as @user, scope: :user
  end

  test "the owner shares a deck and gets a link to copy" do
    visit deck_path(@deck)

    find(".deck-actions-bar .dropdown button", text: "Actions").click
    click_on "Share…"
    check "shared"

    assert_field "share-url", with: deck_url(@deck)
    assert_predicate @deck.reload, :shared?
  end
end
```

- [ ] **Step 2: Run and watch them fail**

Run: `bin/rails test test/controllers/decks_controller_test.rb -n "/shar/"`
Expected: FAIL — `undefined method 'share_deck_path'`.

- [ ] **Step 3: Add the route**

Inside the `resources :decks` block:

```ruby
    patch :share, on: :member
```

- [ ] **Step 4: Add the action**

In `DecksController`:

```ruby
  def share
    @deck = current_user.decks.find_by!(key: params[:id])
    authorize @deck, :share?

    # The checkbox posts "0" or "1", both truthy if assigned raw.
    @deck.update!(shared: ActiveModel::Type::Boolean.new.cast(params[:shared]))
    render :share, layout: false
  end
```

Create `app/views/decks/share.turbo_stream.erb`:

```erb
<%= turbo_stream.replace Decks::ShareModal::FRAME_ID do %>
  <%= render Decks::ShareModal.new(deck: @deck) %>
<% end %>
```

- [ ] **Step 5: Write the modal**

**Do not use `Ui::Modal` here.** It renders a plain `div.modal` whose visibility another controller toggles — that is the scanner modal's pattern. A modal opened from the actions dropdown should be a real `<dialog>`, which is what `Decks::ResultModal` does: a raw `dialog` carrying a Stimulus target, with the controller calling `showModal()`. Follow that.

Create `app/views/components/decks/share_modal.rb`. It must say what sharing *does*, not merely offer a link — `/decks/shared` lists every shared deck, so this is publishing:

```ruby
module Decks
  class ShareModal < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "deck-share".freeze

    def initialize(deck:)
      @deck = deck
    end

    def view_template
      # A <dialog> with a target the share-modal controller opens, like Decks::ResultModal —
      # not Ui::Modal, which is a div whose display another controller flips.
      dialog(class: "share-modal", data: { share_modal_target: "dialog" }) do
        div(class: "share-modal-content") do
          h2 { "Share this deck" }

          # The frame is inside the dialog so the PATCH can replace the toggle and the link
          # without closing the dialog the user is looking at.
          turbo_frame_tag(FRAME_ID) do
            form_with url: share_deck_path(@deck), method: :patch, data: { turbo_frame: FRAME_ID } do
              check_box_tag :shared, "1", @deck.shared?, id: "shared", onchange: "this.form.requestSubmit()"
              label_tag :shared, "Share this deck publicly"
            end

            # Sharing publishes: the deck is listed at /decks/shared, not merely reachable by
            # anyone holding a link. Say so, and say what becomes visible — the description in
            # particular is free text often written while the deck was private.
            p(class: "share-explainer") do
              plain "A shared deck is listed publicly on the shared decks page. Its name, " \
                    "description, format, archetype and card list become visible to anyone. " \
                    "Your results, your collection and your proxy counts do not."
            end

            share_link if @deck.shared?
          end

          button(class: "btn btn-secondary btn-sm", data: { action: "share-modal#close" }) { "Close" }
        end
      end
    end

    private

    def share_link
      div(class: "share-link") do
        input(type: "text", id: "share-url", value: deck_url(@deck), readonly: true, class: "form-input")
        button(
          class: "btn btn-secondary btn-sm",
          data: { controller: "clipboard", clipboard_text_value: deck_url(@deck), action: "clipboard#copy" }
        ) { "Copy link" }
      end
    end
  end
end
```

The `clipboard` controller already prefers a static `text` value over `url`, so the copy button needs no new JavaScript. The dialog does — create `app/javascript/controllers/share_modal_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Opens the share dialog from the deck's actions dropdown. Same shape as the open/close half
// of result_modal_controller.js; the sharing itself is a form POST, so there is nothing else
// here.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
```

No registration step: `app/javascript/controllers/index.js` calls `eagerLoadControllersFrom("controllers", application)`, so the file is picked up by name.

- [ ] **Step 6: Wire the entry point and the badge**

In `Decks::ActionsDropdown`, between `edit_item` and `duplicate_item`:

```ruby
          share_item
```

```ruby
    def share_item
      button(class: "dropdown-item", data: { action: "share-modal#open" }) { "Share…" }
    end
```

Render `Decks::ShareModal` from `Decks::ShowView` beside `Decks::ResultModal`, and add `share-modal` to that view's `data-controller` list:

```ruby
      div(class: "deck-show-container", data: {
        controller: "card-preview deck-totals result-modal tournament-pdf deck-proxies share-modal",
```

```ruby
        render Decks::ResultModal.new(deck: @deck)
        render Decks::ShareModal.new(deck: @deck)
        render Decks::TournamentPdfModal.new(deck: @deck, tournament_profiles: @tournament_profiles)
```

`Decks::PublicShowView` renders neither — it has no actions dropdown to open one from, and `share?` is `owner?`.

In `Decks::ClassificationBadges#view_template`, after the format badge:

```ruby
        # Owner views only — this component is never rendered on a public surface.
        span(class: "badge") { "Shared" } if @deck.shared?
```

- [ ] **Step 7: Run, sabotage, commit**

Run: `bin/rails test test/controllers/decks_controller_test.rb` and `bin/rails test:system test/system/deck_sharing_test.rb` at both viewports.

Sabotage: change the action to `@deck.update!(shared: params[:shared])`. The unshare test must FAIL, because `"0"` is truthy. Restore.

```bash
git add config/routes.rb app/controllers/decks_controller.rb app/views test/controllers test/system
git commit -m "Let the owner share a deck, and say what sharing means

The modal carries the toggle and the link together, because that is the
gesture. It also states that a shared deck is *listed* publicly rather
than merely reachable — /decks/shared publishes it — and names what
becomes visible, the description included: free text usually written while
the deck was private.

The param is cast explicitly: the checkbox posts \"0\", which is truthy."
```

---

## Task 10: the fourth search group

**Files:**
- Modify: `app/services/search/global.rb`
- Modify: `app/views/components/search/results_list.rb`
- Test: `test/services/search/global_test.rb`

**Interfaces:**
- Produces: `Search::Global::Result` with `shared_decks` and `shared_deck_total` added; `Search::Global.call(user: nil, …)` supported.

- [ ] **Step 1: Write the failing tests**

```ruby
  test "a visitor searches cards and shared decks, and nothing personal" do
    decks(:two).update!(user: users(:two), shared: true, name: "Zoroark Box")

    result = Search::Global.call(user: nil, query: "Zoroark")

    assert_empty result.decks
    assert_equal 0, result.deck_total
    assert_empty result.tournaments
    assert_equal [ "Zoroark Box" ], result.shared_decks.map(&:name)
  end

  test "a member's own shared deck appears once, in their own group" do
    mine = decks(:one)
    mine.update!(user: users(:one), shared: true, name: "Zoroark Box")

    result = Search::Global.call(user: users(:one), query: "Zoroark")

    assert_equal [ mine ], result.decks
    assert_empty result.shared_decks
    # Without where.not(user:) this is 2, and Search::ResultsList would emit the same DOM id
    # twice for it.
    assert_equal 1, result.deck_total + result.shared_deck_total
  end

  test "the shared group carries the preloads its rows need" do
    decks(:two).update!(user: users(:two), shared: true, name: "Zoroark Box")

    result = Search::Global.call(user: nil, query: "Zoroark")
    deck = result.shared_decks.first

    assert_predicate deck.association(:standard_pool), :loaded?
    assert_predicate deck.association(:archetype), :loaded?
  end
```

- [ ] **Step 2: Run and watch fail**

Run: `bin/rails test test/services/search/global_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'decks' for nil` on the visitor case.

- [ ] **Step 3: Widen the service**

The nil guards on `deck_scope` and `tournament_scope` already landed in Task 4. This task adds the group itself.

In `app/services/search/global.rb`, extend the `Data.define` with `:shared_decks, :shared_deck_total`, add them to `empty_result` and to `#total`, and:

```ruby
      shared_decks = shared_deck_scope.order(:name).limit(@limit)
        .includes(:archetype, standard_pool: [ :first_card_set, :last_card_set ]).to_a
```

```ruby
      Result.new(
        # …existing keys
        shared_decks: shared_decks,
        shared_deck_total: total_for(shared_deck_scope, shared_decks),
        # …
      )
```

with the new scope:

```ruby
    # Excluding the searcher's own decks is what keeps one deck out of two groups of the same
    # result list — and Search::ResultsList derives its option ids from the deck, so a
    # duplicate would emit one DOM id twice.
    def shared_deck_scope
      @shared_deck_scope ||= begin
        scope = Deck.shared
        scope = scope.where.not(user: @user) if @user
        scope.search(@query)
      end
    end
```

Note the cost this adds, so nobody is surprised by it later: `total_for` re-runs a `count` as soon as a page fills its cap, so a query broad enough to return five shared decks pays for the page **and** for the total — up to two extra scans per keystroke, not one.

`search` must stay **before** any `includes` — `#or` refuses relations that do not carry the same includes.

- [ ] **Step 4: Render the group**

In `app/views/components/search/results_list.rb`, add `shared_deck_group` to the render order and:

```ruby
    def shared_deck_group
      render ResultGroup.new(
        key: "shared_decks", label: "SHARED DECKS", records: @results.shared_decks,
        total: @results.shared_deck_total, index_path: shared_decks_path(q: query),
        see_all_label: see_all_label(@results.shared_deck_total, "shared deck")
      ) do |deck|
        option_row(
          # A distinct prefix, so this group cannot collide with the one above even if the
          # exclusion in Search::Global is ever relaxed. Cheaper than relying on it.
          dom_id: "spotlight-option-shared-deck-#{deck.id}",
          path: deck_path(deck),
          name: deck.name,
          meta: [ deck.format_label, deck.archetype&.name ].compact.join(" · ")
        )
      end
    end
```

- [ ] **Step 5: Run, sabotage, commit**

Run: `bin/rails test test/services/search/ test/controllers/search_controller_test.rb` and `bin/rails test:system test/system/spotlight_search_test.rb` at both viewports.

Sabotage: drop `where.not(user: @user)`. The "appears once" test must FAIL. Restore.

```bash
git add app/services/search/global.rb app/views/components/search/results_list.rb test/services
git commit -m "Search other people's shared decks, in a group of their own

A nil user searches cards and shared decks and queries nothing personal.
A member's own shared deck stays in their own group: without the
exclusion it lands in both, and ResultsList would emit one DOM id twice.
The new group prefixes its ids anyway, so relaxing that exclusion later
breaks a product rule rather than the keyboard navigation."
```

---

## Task 11: the dashboard everyone lands on

**Files:**
- Modify: `app/controllers/home_controller.rb`, `config/routes.rb`
- Modify: `app/views/components/home/dashboard_view.rb`
- Delete: `app/views/home/welcome.html.erb`, `app/views/components/home/welcome_view.rb`
- Test: `test/controllers/home_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
  test "a visitor gets search, a showcase and a way in — and nothing personal" do
    shared = decks(:two)
    shared.update!(user: users(:two), shared: true, name: "Showcased")

    get dashboard_path

    assert_response :success
    assert_select ".spotlight"
    assert_select ".dashboard-showcase a", text: "Showcased"
    assert_select "a[href=?]", new_user_session_path
    assert_select ".dashboard-card", count: 0
    assert_select "#scanner-modal", count: 0
    assert_select "h1", text: /@/, count: 0
  end

  test "the showcase never lists a private deck" do
    decks(:two).update!(user: users(:two), shared: false, name: "Private")

    get dashboard_path

    assert_select ".dashboard-showcase a", text: "Private", count: 0
  end

  test "root is the dashboard for everyone" do
    get root_path
    assert_response :success

    sign_in users(:one)
    get root_path
    assert_response :success
    assert_select ".dashboard-card"
  end
```

- [ ] **Step 2: Run and watch fail**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: FAIL — no showcase, and `root_path` still renders the welcome page.

- [ ] **Step 3: Load the showcase**

```ruby
  SHOWCASE_LIMIT = 6

  def dashboard
    authorize :dashboard, :show?
    @pending_deck_imports = current_user ? current_user.imports.deck_imports.pending : []
    # Both bounds of the pool, not just the pool: the format badge names it from
    # StandardPool#name, which reads them — three extra queries per Standard deck otherwise.
    @shared_decks = Deck.shared.order(created_at: :desc).limit(SHOWCASE_LIMIT)
                        .includes(archetype: [ :primary_card, :secondary_card ],
                                  standard_pool: [ :first_card_set, :last_card_set ])
  end
```

- [ ] **Step 4: Split the view**

`Home::DashboardView` takes `current_user:` (nullable) and `shared_decks:`, and its `view_template` becomes:

```ruby
    def view_template
      div(class: "dashboard-container", data: { controller: "decks" }) do
        if @current_user
          # The only place on this page that prints an email — decision 7 forbids one on a
          # public surface, so it lives inside this branch rather than above it.
          h1 { "Welcome, #{@current_user.email}" }
        else
          h1 { "Cartodex" }
          p { "Your Pokémon Trading Card Game Manager" }
        end

        render Search::Spotlight.new

        if @current_user
          signed_in_grid
        else
          visitor_call_to_action
        end

        showcase if @shared_decks.any?

        if @current_user
          render Ui::DeckImport.new(pending_imports: @pending_deck_imports)
          scanner_modal
        end
      end
    end
```

with `signed_in_grid` holding today's `dashboard-grid` (collection card and decks card, unchanged), and:

```ruby
    def visitor_call_to_action
      div(class: "auth-buttons") do
        link_to "Sign In", new_user_session_path, class: "btn btn-primary"
        link_to "Sign Up", new_user_registration_path, class: "btn btn-secondary"
      end
    end

    def showcase
      section(class: "dashboard-showcase") do
        h2 { "Recently shared decks" }
        div(class: "dashboard-showcase-grid") do
          @shared_decks.each do |deck|
            link_to deck.name, deck_path(deck), class: "dashboard-showcase-deck"
          end
        end
        link_to "See all shared decks", shared_decks_path, class: "btn btn-secondary btn-sm"
      end
    end
```

Update `app/views/home/dashboard.html.erb` to pass `shared_decks: @shared_decks`.

- [ ] **Step 5: Delete the welcome page and point root at the dashboard**

Delete `app/views/home/welcome.html.erb` and `app/views/components/home/welcome_view.rb`, remove `#welcome` from `HomeController` and its name from `publicly_reachable`, and in `config/routes.rb`:

```ruby
  # The visitor dashboard carries the Sign in / Sign up buttons, so the old welcome page said
  # nothing the dashboard does not. `/dashboard` stays alongside it: the navbar brand and
  # existing bookmarks name it, and two routes onto one action cost nothing.
  root "home#dashboard"
```

Check nothing else references `Home::WelcomeView` or a `welcome` route: `grep -rn "WelcomeView\|welcome" app/ test/ config/`.

- [ ] **Step 6: Run everything, both viewports, sabotage, commit**

Run: `bin/rails test && bin/rubocop && bin/brakeman --no-pager && bin/importmap audit`
Then: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`

Sabotage: hoist the `h1 { "Welcome, #{@current_user.email}" }` out of the branch. The visitor test must FAIL on `NoMethodError` or on the `/@/` assertion. Restore.

```bash
git add app/controllers/home_controller.rb config/routes.rb app/views test/controllers
git commit -m "Make the dashboard the page everyone lands on

Signed out it is search, a showcase of recently shared decks and a way
in — no collection card, no deck card, no import, no scanner, and no
email in the heading. The welcome page is deleted because it no longer
said anything the dashboard does not, and root points at the dashboard
for everyone."
```

---

## Definition of done for Stage 2

- A visitor can open a shared deck's link, read the decklist, and copy it for TCG Live.
- A visitor on a private deck's key, an unknown key, or a stranger's private deck gets the **same** 404 body.
- `/cards`, `/cards/:id`, `/dashboard`, `/search`, `/decks/shared` all answer without a session; every other route still redirects to sign-in, asserted per action.
- No public surface renders an allocation control, a printing picker, a proxy badge, an email address, or a win/loss record.
- Every response carries `X-Robots-Tag: noindex, nofollow`; `public/robots.txt` disallows nothing.
- `bin/rails test`, `bin/rubocop`, `bin/brakeman --no-pager`, `bin/importmap audit` pass.
- `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system` both pass.
- Every new test has been seen red once, deliberately.

## Update the documentation last

`CLAUDE.md` describes the app's architecture and is the file the next session reads. Add, in one commit at the end: the `key` as a deck's address and where the single unscoped lookup lives; `decks.shared` with the reason the scopes are hand-written; `PubliclyReachable` and the three things it ties together; the policies and why none of them grants admin anything; the app-wide `noindex` and why `robots.txt` stays permissive; and the deferred scope on #142.
