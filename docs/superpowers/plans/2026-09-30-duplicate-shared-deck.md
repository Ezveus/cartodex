# Duplicate a shared deck — plan

Spec: `docs/superpowers/specs/2026-09-30-duplicate-shared-deck-design.md`.

One lane: about six files. Dispatching two agents over that costs more than it returns.

## Contract

- `Decks::Duplicator.call(deck, user:)` makes the copy for `user`. `user == deck.user` means "own
  deck"; anything else, `nil` owner included, means "somebody else's shared deck".
- `DeckPolicy#duplicate? = user.present? && show?`
- `Decks::PublicShowView.new(deck:, can_duplicate: false)`

## Steps

1. **Duplicator** (`app/services/decks/duplicator.rb`, `test/services/decks/duplicator_test.rb`)
   - Take `user:`. `own = @user.id == @deck.user_id`.
   - Build the attributes: `name` (prefixed only when `own`), `description`, `physical` and
     `tcg_live` (only when `own`), format / `other_format_name` / `standard_pool_id` (always), and
     `archetype_id` (the standing's archetype, else the column).
   - Create it with `@user.decks.create!`.
   - Tests:
     - own copy keeps the archetype;
     - a member's shared deck copied by another member belongs to that member, is private, keeps
       the name verbatim, and carries no description, `physical` or `tcg_live`;
     - the format, `other_format_name` and pool are carried;
     - the printings are carried (a second printing of one card stays distinct);
     - `owned_copies` is 0 on each row;
     - a field list's copy takes the standing's archetype when the column disagrees;
     - a field list with no standing falls back to the column.
2. **Policy** (`app/policies/deck_policy.rb`, `test/policies/deck_policy_test.rb`)
   - A stranger may duplicate a shared deck. A visitor may not. Nobody but the owner may duplicate
     a private deck. Adjust the "sharing exposes no writes" list.
3. **Controller** (`decks_controller.rb#duplicate`, `test/controllers/decks_controller_test.rb`)
   - `Deck.find_by!(key:)`, `authorize`, `Decks::Duplicator.call(source, user: current_user)`.
   - Tests:
     - a member copies a stranger's shared deck (count +1, owned by the member, redirect);
     - a member copies a field list;
     - a stranger's private deck is still a 404 with no row created (existing test);
     - a visitor POSTing is redirected to sign-in with no row created;
     - `public_access_test` keeps `duplicate` behind the session.
4. **View** (`public_show_view.rb`, `app/views/decks/public_show.html.erb`, controller/system tests)
   - Render `button_to "Copy to my decks"` inside `.deck-actions-bar` when `can_duplicate`.
   - Tests:
     - a signed-in stranger sees the button;
     - a visitor does not;
     - a system test clicks it and lands on the owner page of a new deck named like the source,
       on both viewports.
5. CLAUDE.md: the fourth unscoped lookup, the archetype rule, and the policy change.
