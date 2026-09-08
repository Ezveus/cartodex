# Social previews, and an icon that is not Rails' red circle

A Cartodex link pasted into a chat renders as the app's title, its domain, and a **red disc** —
`public/icon.svg`, which is still the 122-byte `<circle fill="red"/>` that `rails new` writes.
Nothing in the app emits an Open Graph tag, so the crawler has no image to prefer and falls back
to the `apple-touch-icon`. The ugly icon and the missing preview are one bug seen twice.

This spec ships both halves: a designed icon, and a composed 1200×630 preview banner for the
three public surfaces that have artwork to show — a deck, an archetype, a card. Everything else
gets a static Cartodex banner.

This is the Open Graph half of the "Discovery and SEO" paragraph of #142, and only that half.
**Indexability is deliberately untouched**: every response still carries
`X-Robots-Tag: noindex, nofollow` (`XRobotsTagMiddleware`) and the matching meta tag, and
`public/robots.txt` still disallows nothing on purpose. Link unfurling and search indexing are
different questions with different answers, and the screenshot that opened this work is the
evidence they are independent — WhatsApp parsed the page, read the icon link, and rendered a
preview, all under a `noindex` it had no reason to honour.

## Measurements

Everything numeric below is command output. The libvips figures come from a throwaway container
built from `ruby:3.4.1-slim` plus line 19 of the `Dockerfile` verbatim — the production base
image, reproduced rather than assumed.

| Question | Answer | How |
|---|---|---|
| Does the production image have libvips, with SVG support? | **Yes** — 8.14.1, `svgload` present | `Vips.type_find("VipsOperation", "svgload")` in that container |
| How many apt packages must be added? | **None.** DejaVu fonts and `fc-list` already arrive as libvips dependencies | `ls /usr/share/fonts`, `command -v fc-list` |
| Does `font: "Archivo ExtraBold 76"` alone render Archivo? | **No — it silently renders DejaVu.** Same string measures 492×342 under `"Archivo ExtraBold 76"` and under `"DejaVu Sans Bold 76"`: identical, i.e. the fallback | `Vips::Image.text(...).size` for both families |
| Does `fontfile:` load a font from the repo? | **Yes** — 437×320, and byte-identical to installing the TTF system-wide and asking for the family by name | same, three ways |
| Can SVG `<text>` wrap a long title? | **No.** librsvg has no line breaking; a 38-character deck name ran off the 1200px canvas | rendered, then looked at |
| Can `Vips::Image.text`? | **Yes** — `wrap: :word, width: 520` → 437×320 | same |
| What does the output weigh? | PNG **443 KB** · palettised PNG **112 KB** · **JPEG Q85 92.8 KB** · JPEG Q78 78.5 KB | `write_to_file` per format, same image |
| What does a render cost? | layout B **444 ms**, of which the gaussian blur is roughly four fifths; the two discarded layouts were 86 ms and 123 ms | `Benchmark.realtime` |
| What does an art cost to fetch? | **60–90 ms, 160–170 KB**, per card, from Limitless' CDN | `curl -w %{time_total}` ×3 |
| What does a cold banner cost end to end? | **~600 ms** — two fetches plus one render | sum of the two above |
| What resolution is the source art? | **460×640 PNG** — the same numbers as `deck_image_export_controller.js`'s `CARD_WIDTH`/`CARD_HEIGHT` | the fetched files |
| Does anything emit an og tag today? | No | `grep -rn "og:\|twitter:" app/` |

The 460×640 figure is the reason the banner's background is blurred. The illustration window of a
card is about 410×230 of those pixels; filling 1200×630 with it is a 2.9× upscale, which is soft
whether or not we ask for it. Blurring is therefore not decoration — it is the honest rendering of
the only source we have, and it buys a per-deck background colour for free.

## The icon

A playmat, seen slightly turned: the dark mat with its centre line, five bench slots, and the
**active Pokémon standing upright in brand red**, breaking the mat's angle. The 1 + 5 arrangement
is unique to this game, so it reads instantly to a player, and it is six aligned blocks, so it
survives being 16 pixels wide.

`public/icon.svg` is the source of truth:

```svg
<svg width="512" height="512" xmlns="http://www.w3.org/2000/svg">
  <g transform="rotate(-11 256 256)">
    <rect x="48" y="112" width="416" height="304" rx="32" fill="#0E1320"/>
    <rect x="88" y="286" width="336" height="6" rx="3" fill="#28324A"/>
    <rect x="68"  y="304" width="64" height="90" rx="10" fill="#93A0B4"/>
    <rect x="146" y="304" width="64" height="90" rx="10" fill="#93A0B4"/>
    <rect x="224" y="304" width="64" height="90" rx="10" fill="#5A6678"/>
    <rect x="302" y="304" width="64" height="90" rx="10" fill="#93A0B4"/>
    <rect x="380" y="304" width="64" height="90" rx="10" fill="#93A0B4"/>
  </g>
  <rect x="204" y="96" width="104" height="146" rx="16" fill="#DD2C16"/>
</svg>
```

Every colour is a design token: `--ink-900`, `--ink-700`, `--ink-300`, `--ink-500`, `--flare`.

**The bench does not survive small sizes, and that is measured, not feared.** Rendered at 84px
inside the banner spike, the five slots collapsed into indistinguishable grey pips. So there are
two drawings, not one: `public/icon.svg` as above for anything large, and
`public/icon-small.svg` — mat plus centre line plus active, **no bench** — behind the 16 and 32
pixel PNGs. `bin/rails icons:build` rasterises both through the vips dependency this change adds
anyway, and the PNGs are committed; the task exists so the derived files cannot drift from the
SVGs unnoticed, not because anything runs it at boot.

Deliverables: `icon.svg`, `icon-small.svg`, `icon-512.png`, `icon-192.png`, `icon-32.png`,
`icon-16.png`, and `icon-maskable-512.png`. `Layouts::ApplicationLayout`'s three `link` tags gain
`sizes`.

**`app/views/pwa/manifest.json.erb` is worse than the favicon and gets fixed here too.** Both of
its `icons` entries point at `/icon.png` and both declare `512x512`, so the `maskable` entry is
the same full-bleed drawing — which Android crops to a circle, taking the mat's corners with it.
The maskable variant is therefore its own file, the mark scaled to the inner 80% with `--ink-900`
bleeding to the edges. And `theme_color` and `background_color` are both the literal string
`"red"`, straight from the generator: the installed app's splash screen is the red disc, full
screen. They become `--ink-900` and `--flare`.

## The banner

Layout, at 1200×630: the primary card's illustration window, upscaled, blurred and darkened,
fills the frame; a vertical scrim runs from 45% to 96% `--ink-900` opacity; the two cards sit
whole and slightly turned on the right, in the icon's own axis; the title, the subtitle and the
white icon sit on the left. A 10px `--flare` rule crosses the top.

Three rules the spike forced, each of which would otherwise be discovered in production:

**Text goes through `Vips::Image.text`, never through SVG `<text>`.** The SVG carries geometry —
background, scrim, rule, logo — and nothing else. This is the one place where "the mockup is the
implementation" does not hold, and it holds everywhere else.

**Every `Vips::Image.text` call passes `fontfile:`.** `vendor/fonts/Archivo.ttf` (SIL OFL 1.1,
committed with its licence) is the file. Omitting it does not fail — it renders DejaVu, correctly,
silently, at slightly different metrics. Nothing about the output says the brand font was not used.

**The scrim adapts to the artwork.** The title is `--paper` on whatever colour the card happens to
be, and a pale illustration would put white text on near-white. So the renderer measures rather
than hopes: it crops the blurred background to the text column, converts to `b_w`, reads `.avg`,
and computes the WCAG contrast ratio against `--paper`. While that ratio is **below 4.5:1** it
darkens the scrim one step down the ladder `[0.45, 0.60, 0.75, 0.88, 0.96]` of top-stop opacity
(the bottom stop tracks it, staying 0.04 from opaque). Five steps take the darkest realistic art
to near-black, so the loop terminates by construction. The threshold and the measurement are the
testable part; the ladder is a tuning table.

Output is `jpg[Q=85]`: 92.8 KB against the PNG's 443 KB, for a photographic image where nobody can
see the difference.

Fewer than two arts is normal — a deck with one notable Pokémon, a card page — and the layout
takes 0, 1 or 2. Zero resolvable arts falls back to the static Cartodex banner.

### What each surface says

| Surface | Title | Subtitle | Artwork |
|---|---|---|---|
| `/decks/:key` | deck name | card count · format, and the pool's name when Standard | the archetype's primary and secondary cards; failing that, the deck's own two most notable Pokémon |
| `/archetypes/:slug` | archetype name | — | the archetype's primary and secondary cards |
| `/cards/:id` | card name | set name · number | the card |

The deck's fallback ranking is `Decks::ArchetypeDetector`'s *suggestion* order, copied exactly:
`[rule_box ? 0 : 1, -hp, -quantity]` — rule-box Pokémon first, then highest HP, then most copies
(`archetype_detector.rb:50`). Not "by copies", which is what this spec said in its first draft and
which would have been a fourth, silently different notion of "the notable Pokémon" in an app that
already has one. Whether the two callers share code or share a documented sort is an
implementation call; agreeing with that line is not. It reads the already-loaded `deck_cards` and
adds no query.

**An archetype's banner carries no list count**, though the page is full of them. The number
depends on which Standard pool the reader has selected, so a number baked into a shareable image
would be a number from a context the image cannot show — the trap
`docs/architecture/archetype-metagame.md` already describes for the pool option's own label.

## What the `<head>` emits

`Layouts::ApplicationLayout` is installed as `layout -> { Layouts::ApplicationLayout }` and
instantiated with no arguments, so the payload cannot be a constructor argument. It arrives the way
`search_overlay?` already does: **the layout asks its host controller.** A concern
`OgPreviewHost`, shaped exactly like `SearchOverlayHost`, exposes `og_preview` as a value helper
returning `nil`, and `DecksController`, `ArchetypesController` and `CardsController` override it.
`content_for(:head)` was the alternative and is rejected: it works, but capturing a nested Phlex
component into a Rails content buffer is a bet, and there is an established pattern here that is
not.

`Ui::OgTags` emits `og:title`, `og:description`, `og:type`, `og:url`, `og:image` with its
`:width`, `:height` and `:type`, plus `twitter:card` and `twitter:image`. It is rendered only when
`og_preview` is present.

**`og:image` is emitted only when the subject is publicly readable** — for a deck, `shared?`. Not
`show?`: an owner reading their own private deck would otherwise be served a page advertising an
image that every crawler is refused, which renders worse than no tag at all. Archetypes and cards
are public outright, so theirs is unconditional.

## Generation and cache

Three objects, one of which knows about libvips:

- **`Og::Payload`** — a value object: `title`, `subtitle`, `art_urls` (0 to 2), `digest`. Built by
  `Og::DeckPayload`, `Og::ArchetypePayload` and `Og::CardPayload`. All the product knowledge lives
  here and none of the drawing does.
- **`Og::Renderer`** — takes a payload, fetches the arts through the existing `HttpFetcher`,
  composes, returns JPEG bytes. The only file that requires `vips`.
- **`Og::Cache`** — `storage/og/<kind>/<id>-<digest>.jpg`, inside the `cartodex_storage` volume
  Kamal already mounts at `/rails/storage`, so a deploy does not throw the work away. On write it
  deletes the subject's other `<id>-*` files: the cache is bounded by construction and needs no
  sweep.

The digest covers the subject's `updated_at`, the ids and `image_url`s of the cards actually
chosen, **and a `LAYOUT_VERSION` constant**. Without that last term, editing the design would
leave every already-generated file in place and the change would appear to do nothing.

The digest also travels in the URL as `?v=<digest>`, because chat clients cache previews by URL.
A banner whose inputs changed therefore has a new address, which is the only thing that makes a
renamed deck's preview update anywhere.

**`v` is a cache-buster and never a lookup key.** The controller ignores it entirely and derives
the current digest from the record, because the two facts above are in tension: a client that
cached `?v=<old>` will re-request exactly that URL, and `Og::Cache` has by then deleted the old
file. Treating `v` as the key would answer that request with a 404 — that is, every preview would
break precisely once, at the moment the deck changed, for every client that had already seen it.
Ignoring it means a stale URL renders the current banner, which is the behaviour a cache-buster
is supposed to have.

Generation is on demand, on the first request, and the measurement above is why: ~600 ms cold,
once, then a file. Pre-generating on `#share` was considered and dropped — it puts a job and a
failure mode on the write path to save 600 ms on a read that happens at most once per link.

## The public endpoint

`OgImagesController`, three actions, its own file because it is a distinct surface: no session, no
HTML, entirely cacheable, and the only endpoint in the app that renders an image from scratch.

- `include PubliclyReachable`; `publicly_reachable :deck, :archetype, :card`; every action calls
  `authorize`. Nothing enforces that it must, so `test/controllers/public_access_test.rb` gets a
  case per action, as `CLAUDE.md` requires of the concern's users.
- `DeckPolicy#og_image? = record.shared?`. `ArchetypePolicy#og_image?` and `CardPolicy#og_image?`
  are `true`.
- A refusal answers **404, not 403**. Every other public refusal in the app is already a
  `RecordNotFound` from a scoped lookup; a crawler has no use for the distinction, and the 404
  discloses less about which keys exist.
- `Cache-Control: public, max-age=31536000, immutable`, which the digest in the URL earns.
- `rate_limit to: 60, within: 1.minute`, unauthenticated only, on `RateLimitStore`. **Derived, not
  copied.** Unlike `CardsController#image`'s 300/min, this endpoint is a *generator*: a cold
  request costs two third-party fetches. Legitimate traffic is one request per pasted link, since
  no page links a banner — it exists only inside another page's meta tags — so 60/min is already
  an order of magnitude of headroom, and it caps a hostile client at 120 outbound CDN requests a
  minute.

Routes are `get "/og/decks/:id"`, `/og/archetypes/:id`, `/og/cards/:id`, outside
`authenticate :user`, keyed the way each surface is already addressed: `decks.key`,
`archetypes.slug`, `cards.id`.

## What would stay green if this were implemented wrong

- **`fontfile:` omitted.** The banner renders, in DejaVu, and looks fine to anyone who does not
  know the brand. The test asserts what the spike asserted: the same string measured under
  `"Archivo ExtraBold"` with the fontfile must differ from the same string without it — the only
  assertion that can tell a font from its fallback.
- **A long title overflowing.** Nothing raises; the glyphs are simply painted past the frame and
  cropped. A test renders a name longer than any real one and asserts the text block's width
  stays inside its column.
- **The scrim never adapting.** Dark artwork is the common case, so a hard-coded scrim passes every
  test written with a dark card. The test uses a deliberately pale art and asserts the measured
  contrast, not the chosen opacity.
- **`LAYOUT_VERSION` left out of the digest.** Every test passes on a cold cache. The test writes
  a banner, bumps the constant, and asserts the path changed.
- **`og:image` gated on `show?` instead of `shared?`.** An owner's own tests pass, because an owner
  can fetch it. The test reads a private deck's page **as its owner** and asserts no `og:image` is
  emitted — the inverse of the obvious test, and the only one that fails.
- **The cache growing without bound.** Nothing observable breaks for months. A test writes two
  digests for one subject and asserts the first file is gone.
- **`og_preview` returning a payload for a deck that is not shared.** The tags would be absent
  because `Ui::OgTags` checks too, so the page looks right; the endpoint would still refuse. The
  test asserts the controller's own `og_preview`, not only the rendered page.
- **`v` treated as a lookup key.** Every test passes, because every test asks for the digest the
  record currently has. The failure needs a client holding a *stale* URL, which no natural test
  builds. The test requests a banner, changes the deck, and re-requests the **old** URL, asserting
  a 200 and the new bytes.
- **libvips missing in CI.** The suite errors loudly, which is fine — but only if a test actually
  renders. At least one test must exercise `Og::Renderer` end to end rather than stubbing it.
- **The maskable icon left full-bleed.** Nothing in a browser or a test shows it; the mark is
  simply clipped on an Android home screen. Nothing automated catches this one, so it is a manual
  check written into the plan rather than a test pretending to cover it.

## Deliberately out of scope

- **Indexability, sitemaps and canonical tags.** The other half of #142's SEO paragraph, and a
  larger decision: it means removing a `noindex` that every response currently carries.
- **A preview for tournaments, the dashboard, `/decks/shared`, `/archetypes`.** They get the static
  banner. Artwork for a listing page means choosing a representative row, which is a design
  question none of these pages has answered.
- **Author attribution in the banner.** Blocked on the same missing `User#display_name` as the rest
  of #142; publishing an email address is not an option.
- **Regenerating a banner when a card's art changes upstream.** Only a `force: true` rescrape moves
  an `image_url`, and the digest reads it, so the next request is correct. Nothing pushes.
- **A shared HTTP cache in front of the endpoint.** The disk cache plus an immutable
  `Cache-Control` is the whole design; a CDN is a deployment decision.
- **Animated or per-locale banners.** One image, one language, matching the app.
