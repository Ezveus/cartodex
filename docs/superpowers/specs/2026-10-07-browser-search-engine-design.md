# Cartodex as a browser search engine — design

## Request

Make Cartodex usable as a site search engine in Chromium-based browsers (Chrome, Vivaldi, …). The
engine must run **exactly** the search the ⌘K spotlight runs. The first signed-in page a member
opens after the deploy shows an *info* alert announcing the feature, with a link to `/settings`,
where the setup instructions live.

## Decisions

### The engine lands on `/search?q=…` rendered as a full page (owner's choice)

`GET /search` already *is* the ⌘K search: `SearchController#show` → `Search::Global` with
`DEFAULT_LIMIT`, rendered as `Search::ResultsView` (a Turbo Frame, `layout false`). The spotlight
always sends that request from a form whose `data-turbo-frame` is `search_results`, so it carries a
`Turbo-Frame` header. The action now branches on `turbo_frame_request?`:

- frame request (the spotlight) → unchanged: the frame, no layout;
- anything else (the browser's search engine) → `Search::PageView` inside the application layout,
  rendering the **same** `Search::ResultsList` over the **same** `search_results` call.

Nothing about the query differs between the two — same service, same limit, same groups, same
"See all N" links — so the two surfaces cannot drift: the page is the panel without its frame. The
page renders `ResultsList`, not `ResultsView`, so `search_results` (a DOM id Turbo resolves frames
by) is never on the page twice next to the overlay's own frame (see `SearchOverlayHost`).

A query shorter than `Search::Global::MIN_QUERY_LENGTH` (2) renders nothing in the panel; on a page
that would be a blank screen, so the page says to type at least two characters.

`/search` was the one public page excluded from the "every public HTML page advertises a preview
image" sweep *because* it had no layout. It now has one on the page path, so the exclusion goes.

### OpenSearch autodiscovery

`GET /opensearch.xml` serves an OpenSearch description whose template is
`<root>/search?q={searchTerms}`, and the layout's `<head>` links it (`rel="search"`). Measured from
the published behaviour: Chrome only honours the link **on the site's root**, and registers what it
finds as an **inactive** site search that the member activates in `chrome://settings/searchEngines`.
`/` is `home#dashboard`, which renders the layout, so the link is there. The controller derives the
host from the request (the `Oauth::MetadataController` precedent) and inherits from
`ActionController::Base`, not `ApplicationController` — no session, no Pundit, nothing to authorize.

### `/settings` gets a "Browser search engine" section

`Settings::SearchEngineSection` (`#search-engine`) shows the URL to paste — `<root>/search?q=%s`,
copyable — and short steps for Chrome (and Chromium browsers sharing its settings page) and Vivaldi.
The `%s` is concatenated to `search_url`, never passed through a URL helper, which would escape it
to `%25s` and hand the member a template no browser substitutes.

### The announcement: one column, claimed once, only by a page that will show it

`users.search_engine_announced_at` (datetime, nullable). `nil` means "not announced yet", which is
every member at deploy time and every account created afterwards — both are "the first session
after the deploy" for that member.

The alert is shown and the column written **in the same request, and only by a request that will
actually display it**. Three kinds of request render the layout without the member seeing it, and
each would burn the announcement silently:

- a **Turbo prefetch** (`X-Sec-Purpose: prefetch`): Turbo 8 prefetches every link on hover, and
  nothing in this app disables it — hovering a navbar link would claim the alert in a response the
  member never opens;
- a **Turbo Frame request**: the controllers' layout is a Phlex lambda, so a frame request renders
  the full layout and Turbo keeps only the frame;
- anything not `GET`.

The claim is an atomic `UPDATE … WHERE search_engine_announced_at IS NULL`, and the alert renders
only when that update changed one row — two tabs opening at once show it once. It is guarded by the
in-memory value first, so a member who has seen it costs no write: an unconditional UPDATE on every
page render would take SQLite's single write lock on every page view, forever.

The decision lives in a controller concern, `SearchEngineAnnouncementHost`, exposed as a helper
and registered on `ApplicationComponent`, and is included by **both** layout hosts —
`ApplicationController` and `Oauth::AuthorizationsController` — the same two-host rule as
`SearchOverlayHost` and `OgPreviewHost`.

### The alert itself

A third flash kind, `flash-info`, rendered by `Ui::FlashMessages`. The existing flashes remove
themselves after five seconds (`flash_controller.js`), which is right for "Deck saved" and wrong for
an announcement carrying a link: it carries `data-flash-persistent-value="true"`, which skips the
timer, and a close button wired to `flash#dismiss`.

It is marked seen when shown, not when clicked: "announce at the first session" is a one-time
notice, not a nag.

## Out of scope

- Search suggestions (`application/x-suggestions+json`) in the omnibox.
- Firefox/Safari-specific instructions (OpenSearch discovery covers Firefox anyway).
- A generic announcement system — one column for one announcement; the next one can generalise it
  with two examples in hand.
