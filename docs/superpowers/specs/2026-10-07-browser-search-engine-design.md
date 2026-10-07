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

### The announcement: one column, spent by the browser once it is on screen

`users.search_engine_announced_at` (datetime, nullable). `nil` means "not announced yet", which is
every member at deploy time and every account created afterwards — both are "the first session
after the deploy" for that member.

**Rendering never spends it.** The first version claimed the column while rendering, guarded
against the responses known not to be shown (Turbo hover prefetch, browser prefetch/prerender,
frame requests, non-GET). The adversarial review proved one more no guard can see: when a tracked
asset changes, Turbo **discards** the response of a navigation and reloads the page in full — and
this very deploy changes the importmap. A member whose tab stayed open across the deploy had the
announcement claimed by a page that was thrown away, reproduced against a dev server (`UPDATE`
logged on the first `GET /decks`, full reload, no alert, column set).

So the server shows the alert while the column is nil, and the alert acknowledges itself:
`announcement_controller.js` sends `DELETE /search_engine_announcement` when it connects, which
only happens on a page in the DOM. Every discarded response is covered at once, by construction
rather than by enumeration. Replayed after the change: discarded `GET /decks`, reload `GET /decks`,
then the `DELETE` — and the alert on screen.

- The write is `User#acknowledge_search_engine_announcement!`: an atomic
  `UPDATE … WHERE search_engine_announced_at IS NULL`, so concurrent acknowledgements write once,
  and an in-memory guard so an acknowledged member costs no query. A busy lock leaves it pending
  (`with_brief_write_wait`, rescued), and the alert shows again on the next page.
- The trade: at-least-once instead of at-most-once. Two tabs opened before either acknowledges
  both show it; a failed acknowledgement shows it again. Both are better than an announcement
  spent unseen.
- The element is `data-turbo-temporary`, so a page restored from Turbo's cache (Back) neither
  shows it again nor acknowledges twice.

### The alert itself

A third flash kind, `flash-info`, rendered by `Ui::FlashMessages`. The existing flashes remove
themselves after five seconds (`flash_controller.js`), which is right for "Deck saved" and wrong for
an announcement carrying a link: it carries `data-flash-persistent-value="true"`, which skips the
timer, and a close button wired to `flash#dismiss`.

### Ids on the search page

Once the overlay has searched on `/search`, its panel holds the same rows as the page. Both used
to derive ids from `spotlight-…`, so every option id existed twice and the page's groups were
labelled by the overlay's headers. `Search::ResultsList` takes an `id_prefix:` (default
`spotlight`); the page passes `search-page`.

## Out of scope

- Search suggestions (`application/x-suggestions+json`) in the omnibox.
- Firefox/Safari-specific instructions (OpenSearch discovery covers Firefox anyway).
- A generic announcement system — one column for one announcement; the next one can generalise it
  with two examples in hand.
