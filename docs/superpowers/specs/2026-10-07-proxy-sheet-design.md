# Printable proxy sheet for a deck

## What

A deck's Export menu offers a PDF of its cards laid out for printing on A4, each card printed at
exactly **6 cm × 8.5 cm**. Cut out, a card slides into a sleeve in front of a real card (63 × 88 mm),
which is why it is smaller than one.

Two styles, mirroring the Cardmarket wishlist (#208):

| Style | Copies printed | Who |
|---|---|---|
| `proxy_sheet` | every copy of every card (`quantity`) | anybody `DeckPolicy#export?` lets in — the owner, and anybody on a shared deck |
| `proxy_sheet_missing` | `DeckCard#proxies` on a physical deck, the whole count otherwise | the owner alone (`DeckPolicy#proxy_sheet_missing?`), because `owned_copies` is collection data |

On a non-physical deck the owner's menu shows one item, as with the wishlist: the two would print
the same sheet.

## Layout

A4 is 595.28 × 841.89 pt. A card is `6 / 2.54 × 72 = 170.08` pt wide and `8.5 / 2.54 × 72 = 240.94`
pt tall, so a 3 × 3 grid measures 510.24 × 722.83 pt (18 × 25.5 cm), centred: 1.5 cm side margins,
2.1 cm top and bottom. Nine cards per page; a 60-card deck is seven pages.

Cards **touch**, so one cut serves two cards. Cut marks are drawn in the margins only, extending each
of the grid's four vertical and four horizontal lines, so no mark lands on a card. The margins are
far wider than any printer's unprintable edge (~5 mm).

The image is stretched to the slot, not letterboxed: Limitless's art is 460 × 640 (aspect 0.719), the
slot 0.706, a 1.8 % distortion nobody can see — while a letterbox would leave a white strip inside a
card that is being cut to its edge.

Order is Pokémon, Trainer, Energy (`Decks::Comparator::TYPE_ORDER`), then name, then the printing,
each copy repeated `quantity` times — close to the deck page's, which also splits Trainers by subtype.

The PDF must be printed at **actual size** — any "fit to page" setting scales the cards. The menu
item says so in its label's tooltip; nothing in a PDF can enforce it.

## Measured

On the development catalogue, every one of the 5204 cards carries an `image_url`, all on
`limitlesstcg.nyc3.cdn.digitaloceanspaces.com`, all `.png`. A deck holds 6 to 37 distinct printings
(25 on average). One `_LG` image is 460 × 640, palette PNG with a `tRNS` chunk, ~165 KB, fetched in
~70 ms.

On the 37-printing / 60-card deck:

| Pipeline | Fetch | Convert | Prawn render | Total |
|---|---|---|---|---|
| serial fetch, PNG handed to Prawn | 2.30 s | — | 2.35 s | ~4.7 s |
| 8 threads, PNG → JPEG via libvips, JPEG to Prawn | 0.51 s | 0.21 s | 0.02 s | ~0.75 s |

Prawn decodes a PNG carrying transparency in pure Ruby to split its alpha channel (~63 ms per image);
a JPEG is embedded as-is. The JPEG is flattened onto white first, which also fills the card's
transparent rounded corners — what a cut sheet wants. The PDF weighs 4.7 MB either way. libvips is
already in the production image and in CI for `Og::Renderer`.

## Decisions

- **A member action of its own, `GET /decks/:id/proxy_sheet`**, not a third `style` of `#export`.
  It is the first export that makes outbound requests, and `rate_limit` is keyed by action: sharing
  `"decks-export"` would merge its budget with the clipboard exports. Its own limit,
  `"decks-proxy-sheet"`, is 10/min per IP for visitors (a click, never a prefetch — the link carries
  `data-turbo="false"`), and the owner is not throttled, like every other limit here. The missing
  style is `?missing=1`.
- **The lookup is the existing unscoped shape**, `Deck.find_by!(key:)` then `authorize` on the next
  line — the deck-identity rule, sixth occurrence after `#show`, `#export`, `#odds`, `#duplicate`
  and `#compare`.
- **At most `MAX_PRINTINGS = 60` distinct printings.** A legal deck cannot exceed 60, the largest
  measured is 37; beyond it the request is refused with an alert rather than fetching hundreds of
  images inside a web request.
- **Fetches use `Og::Renderer`'s short timeouts (3 s open, 5 s read) on a pool of 8 threads.** The
  threads touch no Active Record: URLs are read before the pool starts. Those timeouts bound one
  attempt, and Net::HTTP retries an idempotent GET once after a read timeout, so a hung CDN costs
  10 s an image (measured in review) — ~50 s for a 37-printing deck. **`FETCH_DEADLINE = 8` s bounds
  the whole sheet**: past it the request stops waiting and late arts print as placeholders.
- **Any error fetching or decoding one image is that image's placeholder**, not the sheet's 500:
  `HttpFetcher` lets `Net::HTTPBadResponse` through, measured in review.
- **A failed image prints a placeholder, not an error.** The slot gets a thin frame with the card's
  name and `SET NUMBER`, so the sheet is still usable and the reader sees which card failed before
  printing. A failed request (whole PDF refused) would waste the 36 images that did arrive.
- **Nothing to print** (missing style, every copy backed) redirects to the deck with a notice, since
  the link is a plain download and has no clipboard to show a notice in.

## Out of scope

Bleed, other paper sizes, a choice of card size, caching the fetched images.
