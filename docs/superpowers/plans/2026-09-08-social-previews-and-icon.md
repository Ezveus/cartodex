# Plan — social previews, and the icon that replaces Rails' red circle

Design: `docs/superpowers/specs/2026-09-08-social-previews-and-icon-design.md`.
Baseline in this worktree: **1616 runs, 7578 assertions, 0 failures, 0 errors, 0 skips** (22.6 s).

This plan was rewritten after being attacked. The twelve findings are recorded at the bottom; the
body already incorporates them, so the two do not disagree.

## Two corrections to the spec, made before any code

**1. `Ui::OgTags` always renders.** The spec said both that it renders "only when `og_preview` is
present" and that everything outside the three surfaces "gets a static Cartodex banner". Those
cannot both hold. Resolved the second way: `og_preview` never returns nil, its default is a *site*
payload pointing at a committed `public/og-default.jpg`, and a subject's own payload replaces it
only when that subject is publicly readable. This also makes the private-deck case degrade to
Cartodex branding rather than to a bare URL, and puts the policy question in one controller branch
instead of a condition the component repeats.

**2. The digest cannot be built from `updated_at` alone.** Measured: `DeckCard belongs_to :deck`
carries no `touch: true` (`app/models/deck_card.rb:2`), so

```
after DeckCard create:  UNCHANGED
after DeckCard update:  UNCHANGED
after DeckCard destroy: UNCHANGED
after archetype retag:  moved
```

Every write `Api::DeckCardsController` performs — add, remove, requantify, swap a printing — leaves
`deck.updated_at` alone. The banner prints the card count and derives its fallback artwork from the
deck cards, so building a deck would change the banner's content and never its address; under
`Cache-Control: immutable` the stale banner is then permanent. `touch: true` is the tempting fix and
is rejected: it would move `updated_at` on every allocation write app-wide, which is a change to
something else's semantics for this feature's benefit. Instead the deck digest folds in the
**loaded** deck-cards' own state, which costs no query on any page that already preloads them:

```ruby
[ Og::LAYOUT_VERSION, "deck", deck.key, deck.updated_at.to_i,
  deck.deck_cards.size, deck.deck_cards.map { |dc| dc.updated_at.to_i }.max, *art_urls ]
```

## Frozen contract

```ruby
# app/services/og/payload.rb
module Og
  LAYOUT_VERSION = 1

  Payload = Struct.new(:kind, :key, :title, :subtitle, :art_urls, :digest, keyword_init: true) do
    def validate! = ... # raises unless kind/title present, and digest present unless kind == "site"
  end
end
```

- `kind` — `"site" | "deck" | "archetype" | "card"`, String, never a Symbol (Phlex dasherizes
  Symbol attribute *values*, and these reach `content:`).
- `key` — the segment each subject is already addressed by: `decks.key`, `archetypes.slug`,
  `cards.id`. `nil` for `"site"`.
- `title` — String, never blank. `subtitle` — String or nil.
- `art_urls` — `Array<String>`, 0 to 2, each a non-blank remote `card.image_url`.
- `digest` — 16 hex characters; nil only for `"site"`.

`validate!` exists because `Struct.new(keyword_init: true)` **stores `nil` for a missing keyword**
and raises only on an extra one — measured, and written down at `styleguide/page_view.rb:394-398`.
A builder that forgot `digest:` would otherwise produce a cache path `…/key-.jpg` and an empty
`?v=`, silently.

```ruby
Og::SitePayload.call
Og::DeckPayload.call(deck)
Og::ArchetypePayload.call(archetype)
Og::CardPayload.call(card)
Og::Renderer.call(payload)   # => String, JPEG bytes, 1200x630
Og::Cache.fetch(payload)     # => Pathname, rendering on miss
Og::Cache.root               # => Pathname, settable (see the parallel-workers finding)
```

Renderer constants: `WIDTH = 1200`, `HEIGHT = 630`, `TEXT_COLUMN`, `SCRIM_LADDER = [0.45, 0.60,
0.75, 0.88, 0.96]`, `CONTRAST_TARGET = 4.5`, `QUALITY = 85`, `FONT`.

### Mechanics recon and the adversary settled

**Two declarations expose `og_preview` to the layout**, not one: `helper_method :og_preview` in the
concern **and** `register_value_helper :og_preview` on `ApplicationComponent`
(`search_overlay_host.rb:20`, `application_component.rb:27`).

**The layout has two hosts.** `Oauth::AuthorizationsController` descends from Doorkeeper's
controller and includes `SearchOverlayHost` directly for exactly this reason. `OgPreviewHost` goes
on both. Already pinned: `oauth_consent_test.rb:129` renders that screen through the layout.

**The 404 is free.** `PubliclyReachable`'s `included do` installs
`rescue_from ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, with: :not_found`, and an
exception from the action aborts the callback chain before any `after_action`, so `verify_authorized`
cannot raise first. **Do not copy `DecksController`'s override of `not_found`**
(`decks_controller.rb:271`), which redirects a session-less requester to sign-in — right for a page
a human typed, wrong for an image a crawler requested.

**One rate-limit bucket.** The key is `["rate-limit", scope, name, by]` with `scope` defaulting to
`controller_path`, so sibling actions sharing a `name:` share a budget — which is what this endpoint
wants, a cold request costing the same two CDN fetches whichever kind it is.

**`expires_in` supports `immutable:`** natively in actionpack 8.1.3.1 (read from
`conditional_get.rb`), so `expires_in 1.year, public: true, immutable: true`.

**Absolute URLs work in a Phlex component under a real render**: `Phlex::Rails::Helpers::Routes`
delegates `url_options` to the view context, so `*_url` picks up the request's host, and
`config/application.rb:51` sets `default_url_options` from `ENV["URL"]` for the request-less case.

### The preloads

`ArchetypesController#show` already preloads `:primary_card, :secondary_card, :parent, :children`
(`archetypes_controller.rb:116`), so `Og::ArchetypePayload` reading the two member cards costs
**zero** queries — which is the whole budget, because `assert_equal 17` at
`archetypes_controller_test.rb:509`, `:510` and `:652` is a literal, not a comparison.

`DecksController#show` gains, in **both** `owner_show` and `public_show`:

```ruby
archetype: [ :primary_card, :secondary_card ], deck_cards: { card: :pokemon_subtype }
```

`public_show` preloads neither `:archetype` nor the member cards today. This is hygiene, not an
emergency — see finding 1 for why the plan's earlier claim about an N+1 was wrong — and it is a
constant cost that `public_show`'s new literal flat-cost test will pin.

`CardsController#show` already preloads `:pokemon_subtype` and has no flat-cost test.

Numbers to compare before and after: `17 / 17 / [17,17,17]` (archetypes show), `7`
(`cards_controller_test.rb:303`), `9` (`public_show`, measured by the adversary, pinned by this
plan), `17` (`owner_show`), and the four `small == large` pairs in `decks_controller_test.rb`.

## Lanes

Every agent is **write-only** — write code and tests, run nothing — and I run the suite myself,
serialised. The reason is not the one this plan first gave: Rails *does* fork a database per worker
(`storage/test.sqlite3_0` … `_7` on disk). The reason is that two concurrent `bin/rails test`
invocations use the *same* per-worker filenames, so two agents running the suite collide on
`_0…_7`; and this suite is already at its parallel flake limit.

| Lane | Owns | May not touch |
|---|---|---|
| 1 · payloads | `app/services/og/{payload,site_payload,deck_payload,archetype_payload,card_payload}.rb` + their tests | anything else |
| 2 · rendering | `app/services/og/{renderer,cache}.rb` + tests; `Gemfile`; `vendor/fonts/`; **both** apt lines in `.github/workflows/ci.yml`; `test/test_helper.rb`'s `parallelize_setup` | `og/*payload*` |
| 3 · icons | `public/icon*.{svg,png}`, `public/og-default.jpg`, `lib/tasks/icons.rake`, `app/views/pwa/manifest.json.erb` | all Ruby under `app/` |
| seam · me | `og_preview_host.rb`, `ui/og_tags.rb`, `application_layout.rb`, `application_component.rb`, `og_images_controller.rb`, `routes.rb`, the three policies, the three `#show` actions, `public_access_test.rb`, the rate-limit test, both architecture docs | — |

**Lane 2's CI edit is two lines, not one.** `config.eager_load = ENV["CI"].present?`
(`test.rb:16`) means `require "vips"` runs at boot in both the `test` and `system_test_mobile`
jobs (`ci.yml:58`, `:98`). Patching one and not the other is green locally and red in CI only.

Lane 3 rasterises through the Docker container the spike already used, so it is **not** blocked on
`brew install vips`.

## Commits

1. **The icon** — lane 3 plus the layout's `link` tags. No Ruby app code, no dependency.
2. **The banner pipeline** — gem, font, lanes 1 and 2, the endpoint, policies, routes.
3. **The tags** — `OgPreviewHost`, `Ui::OgTags`, the three `#show` overrides, docs.

## Tests

Red first, both outputs reported. The list below is the adversary's output turned into assertions;
where a test is written as the *inverse* of the obvious one, that is deliberate.

### Payloads

- Deck with an archetype → the archetype's two card `image_url`s, primary then secondary.
- Deck without → its own notable Pokémon, `[rule_box ? 0 : 1, -hp, -quantity]` **and
  `.uniq(&:name)`** (`archetype_detector.rb:50-52`). The fixtures hold two Budews and two Froakies
  with different HP, so a payload that copies the sort but drops the `uniq` draws one Pokémon twice
  and `art_urls.size == 2` still passes. The test asserts the two arts have **different names**.
- The fixture cards all have `image_url: nil`, so every art test sets URLs by hand.
- Archetype's primary with no secondary → one art. No Pokémon, or blank `image_url` → `[]`.
- Subtitle names the pool only when `format == "standard"`; the card count comes from
  `deck_cards.sum(&:quantity)` in **Ruby**, not `sum(:quantity)` in SQL, which would bypass the
  preload and add a query.
- **The digest moves when a `DeckCard` is created, requantified or destroyed** — the inverse of what
  this plan first wrote, and the assertion that catches finding 2. Also moves on
  `LAYOUT_VERSION`, on the deck's own `updated_at`, and on a chosen card's `image_url`.
- `validate!` raises on a payload missing `digest`, and every builder test asserts **every** member.

### Rendering and cache

- Output is a 1200×630 JPEG, asserted by loading the bytes back through `Vips`.
- A title longer than any real name stays inside `TEXT_COLUMN`.
- **`fontfile:` is really passed**: the same string measured with and without it must differ in
  width. Nothing else distinguishes Archivo from a silent DejaVu fallback.
- A pale art walks the scrim down the ladder past `CONTRAST_TARGET`; a dark art stays on rung one.
- 0, 1 and 2 arts all render, and the 2-art case asserts on **pixels** — the average luminance of
  the art region differs from the fallback banner's. Without that, the whole compositing half can
  be broken and every controller test still gets a valid JPEG of the fallback.
- A fetch failure degrades to the site banner. The test points at a **real unroutable URL** and lets
  the real `HttpFetcher` run, because the house stubbing idiom
  (`HttpFetcher.define_singleton_method(:call)`) bypasses the real rescues and would only prove the
  renderer catches whatever class the stub chose. The rescue is narrow — `HttpFetcher::FetchError` —
  since that class already covers connection errors (finding 9).
- `Og::Cache.fetch` renders on a miss and reads on a hit, with `Og::Cache.root` pointed at a
  per-test `Dir.mktmpdir`. Without that the test is green in CI and wrong locally, because
  `storage/` is gitignored and survives between runs.
- A second digest for one subject deletes the first file.

### The seam

- Endpoint: shared deck → 200, `image/jpeg`; unshared → 404; unknown key → 404; archetype, card →
  200. **Plus the inverse that discriminates the policy**: `sign_in owner` then
  `get deck_og_image_path(private_deck)` → **404**. Without it, `og_image? = show?` is green
  everywhere, and `og_preview` must therefore branch on `policy(@deck).og_image?`, not on
  `@deck.shared?`, or the policy stays untested.
- `Cache-Control` asserted on the **literal token** `immutable`, not on `max-age`.
- A stale `?v=` answers 200 with current bytes, built from a **fabricated** digest
  (`v: "deadbeefdeadbeef"`) — deriving a real prior digest is vacuous, since `updated_at.to_i` is
  second-resolution and a same-second rename yields the identical digest.
- One `og_images_rate_limit_test.rb` in the house idiom (`with_real_rate_limit_store`, four
  existing siblings): the test cache store is `:null_store`, so without it `rate_limit` is a silent
  no-op and an omitted, mis-numbered or thrice-named limiter is green. It exhausts the budget on
  `#deck` and then asserts `#archetype` is **also** refused — that is what proves one shared bucket.
- **The deliverable files exist**: `assert File.exist?` on `public/og-default.jpg` and on every icon
  the layout's `link` tags name. Asserting the tag says nothing about the file.
- `og:image` on every public row of `public_access_test.rb#public_gets`, iterated — with `/search`
  **explicitly excluded and named**, because `search_controller.rb:9` is `layout false` and gets no
  tags at all. Excluding it in the test is what makes that a decision rather than an oversight.
- New literal flat-cost test on `public_show`, the visitor path nothing measures today: cards
  carrying distinct `pokemon_subtype_id`s and real `image_url`s, `assert_equal 9`.
- The consent screen emits the site `og:image`.

## Docs

`CLAUDE.md` under the frontend section; `docs/architecture/public-surface.md` gains
`OgImagesController` and its rate limit. Every sentence checked against the file it describes.

## Verification

All five CI gates with CI's own invocations, `bin/rubocop` on the files written, both system-test
viewports, then sabotage every new test and report the table. The banner is an image, so I open it;
the icon is checked at 16, 32 and 512.

## What this plan got wrong, found by attacking it before it existed in code

1. **The N+1 it built a lane constraint around does not exist.** No fixture card has a
   `pokemon_subtype` (`cards.yml` references none of `pokemon_subtypes.yml`'s 8 rows), so the
   fallback ranking reads nil and issues nothing: `small=0 large=0` on the exact deck
   `decks_controller_test.rb:559-582` builds. With subtypes wired up the cost is one query per
   *distinct subtype* (measured: 2 for 4 Pokémon), not per card, because `SQLCounter` skips
   `payload[:cached]`. The preload is hygiene. Worse, that test is `owner_show` only — `public_show`
   costs 9 and is measured by **nothing**, which is why this plan now pins it.
2. **The digest never moves when the decklist changes**, and the plan's own test asserted that as
   the requirement. Corrected above; the test is inverted.
3. **The stale-`?v=` test was vacuous.** Second-resolution `updated_at` plus finding 2 means the
   "old" URL is usually the current one, so the test passed under an implementation where `v` *is*
   the lookup key. Now built from a fabricated digest.
4. **`Og::Cache` shared one directory across 8 forked workers**, with no `parallelize_setup` and a
   gitignored directory that survives between runs. Two named cache tests would have deleted each
   other's file and been order-dependent across runs. Root is now overridable.
5. **No rate-limit test at all**, against a `:null_store` that makes `rate_limit` a silent no-op and
   a four-file house idiom the plan ignored.
6. **Nothing asserted the deliverable files exist** — only the tags that point at them. Every page
   could advertise a 404 image with the suite green.
7. **`og_image? = show?` was green on every endpoint test listed**, and the one discriminating test
   only discriminates if the branch reads the policy rather than `shared?`.
8. **"Every page emits an `og:image`" is false**: `/search` is `layout false`, and `AdminLayout` has
   no tags. Now an explicit, named exclusion.
9. **The #107 hazard was stale.** `HttpFetcher` already maps `SocketError`, `Errno::ECONNREFUSED`,
   `Errno::ECONNRESET` and `OpenSSL::SSL::SSLError` to `FetchError` (`e2793c4`). The plan's
   "deliberate `rescue StandardError`" was a defence against a fixed bug; the rescue is narrow, and
   the test uses a real unroutable URL rather than the stub that bypasses those rescues.
10. **Every fixture card has `image_url: nil`**, so all endpoint tests render the zero-art fallback
    and the compositing half could be entirely broken while green. `quiet_archetype` likewise gives
    the `assert_equal 17` pin a card with no art and no secondary.
11. **"Bounded by construction" was true only per subject.** The subject count is not bounded:
    `/og/cards/:id` spans 1806 catalogue cards ≈ 168 MB at 92.8 KB each, in the same Kamal volume as
    the production SQLite databases. The claim is struck from the spec and the ceiling stated.
12. **Three smaller vacuities**: `immutable` needed a literal-token assertion (`expires_in 1.year,
    public: true` alone emits no such token, and a `max-age` regex passes); the fallback selection
    needed `.uniq(&:name)`, without which two printings of one Pokémon are drawn twice past an
    `art_urls.size == 2` assertion; and `deck_cards.sum(:quantity)` in SQL would bypass the preload
    for a number the loaded association already has.

Also corrected: the lane rationale. Rails already forks a test database per worker, so "one SQLite
file, no `TEST_ENV_NUMBER`" was wrong — the real reason agents stay write-only is that two
concurrent runs share those per-worker filenames.
