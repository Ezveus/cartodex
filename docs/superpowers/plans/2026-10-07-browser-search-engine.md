# Browser search engine — implementation plan

Spec: `docs/superpowers/specs/2026-10-07-browser-search-engine-design.md`.
Baseline: 2479 runs, 0 failures (container `cartodex-test:4.0.6`).

One lane, implemented inline: the change is ~12 files, and a server/view split would share the
helper name, the flash markup and the fixtures.

## Contract

- Column `users.search_engine_announced_at :datetime` (nullable, no default).
- `User#claim_search_engine_announcement!` → `true` exactly once per user; returns `false` without
  issuing an UPDATE when the in-memory value is already set; atomic `update_all … WHERE IS NULL`.
- Concern `SearchEngineAnnouncementHost` → `helper_method :search_engine_announcement?`
  (memoized; `user_signed_in? && request.get? && !turbo_frame_request? && !prefetch_request? &&
  current_user.claim_search_engine_announcement!`). Included in `ApplicationController` and
  `Oauth::AuthorizationsController`; `register_value_helper` on `ApplicationComponent`.
- `Ui::FlashMessages` renders `.flash.flash-info[data-flash-persistent-value=true]` with a link to
  `settings_path(anchor: "search-engine")` and a `button.flash-close[data-action=flash#dismiss]`.
- `flash_controller.js`: `static values = { persistent: Boolean }`; `dismiss()`.
- `SearchController#show`: `turbo_frame_request?` → `render :show, layout: false` (frame,
  unchanged); otherwise `render :page` within `Layouts::ApplicationLayout` → `Search::PageView`.
- `GET /opensearch.xml` → `OpensearchController#show`, content type
  `application/opensearchdescription+xml`, template `"#{search_url}?q={searchTerms}"`.
- Layout `<head>`: `link rel=search type=application/opensearchdescription+xml title=Cartodex`.
- `Settings::SearchEngineSection` `#search-engine`, template `"#{search_url}?q=%s"`.
- Fixtures: every existing user fixture carries `search_engine_announced_at`, so the 700-odd
  existing tests keep rendering no announcement; tests needing it nil set it explicitly.

## Tests

1. `UserTest`: claim returns true then false; a second claim issues no UPDATE; a stale in-memory
   copy (second instance) loses the race and returns false.
2. `SearchEngineAnnouncementTest` (integration): first GET shows `.flash-info` linking to
   `/settings#search-engine` and sets the column; second GET shows nothing; prefetch request
   (`X-Sec-Purpose: prefetch`) shows nothing and leaves nil; Turbo-Frame request leaves nil;
   visitor shows nothing; already-announced user shows nothing; admin layout shows it too.
3. OAuth consent page still renders for a member with nil (two-host rule).
4. `SearchControllerTest`: existing frame tests send `Turbo-Frame: search_results`; new: plain
   GET renders `<html>` + navbar + the same option hrefs in the same order as the frame response
   (the "exactly the same search" guard); short query on the page says "at least 2 characters";
   frame response still has no `<html>`.
5. `public_access_test`: drop the `/search` exclusion from the og:image sweep.
6. `OpensearchControllerTest`: unauthenticated 200, content type, template URL, layout head link
   on `/` (root, where Chrome requires it).
7. `SettingsControllerTest`: `#search-engine` section shows `…/search?q=%s` literally (not `%25s`).
8. System: fresh member sees the info alert, it is still there after the 5 s auto-dismiss window
   of other flashes is irrelevant (persistent attribute asserted), close button removes it, link
   reaches the settings section; `/search?q=…` page lists results and a click navigates. Both
   viewports.
