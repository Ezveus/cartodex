# The Open Graph preview images. Its own controller because it is a distinct surface from every
# page in the app: no session, no HTML, one generated image per subject, cached on disk and served
# immutable. It is also the only endpoint here that renders an image from scratch, which is what
# sizes its rate limit.
class OgImagesController < ApplicationController
  include PubliclyReachable

  publicly_reachable :deck, :archetype, :card

  # One bucket for the three actions, not three. The limiter's cache key is
  # ["rate-limit", scope, name, by] with `scope` defaulting to controller_path, so a shared `name:`
  # is a shared budget — which is what this endpoint wants, since a cold request costs the same two
  # CDN fetches whichever kind it is.
  #
  # 60/min is derived, not copied from CardsController#image's 300. No page *links* a banner: it
  # exists only inside another page's <head>, so legitimate traffic is one request per pasted link,
  # a handful a minute at most. 60 is already two orders of magnitude of headroom for a reader and
  # caps a hostile client at 120 outbound fetches a minute.
  RATE_LIMIT_TO = 60
  RATE_LIMIT_WITHIN = 1.minute

  # No `unless: -> { user_signed_in? }`, and this is the one place this app's own rate-limit idiom
  # is deliberately not followed. Every other limiter here exempts members because members are who
  # those endpoints serve; this one is fetched by crawlers, which never carry a session. So the
  # exemption would buy legitimate traffic exactly nothing while lifting the cap off the only
  # caller in a position to abuse a generator — a signed-in member could otherwise walk
  # /og/cards/:id across the whole catalogue: ~1800 renders, ~3600 outbound CDN fetches and ~170 MB
  # into the volume that holds the production databases, all on request threads.
  rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "og-image", store: RateLimitStore, only: [ :deck, :archetype, :card ]

  # A refusal answers 404 and needs no code: PubliclyReachable's `included do` already routes both
  # RecordNotFound and Pundit::NotAuthorizedError onto the static 404, so an unknown key and a
  # private deck are indistinguishable. Note that this controller must *not* copy
  # DecksController's override of #not_found, which redirects a session-less requester to the
  # sign-in page — right for a page a human typed, wrong for an image a crawler asked for.
  # `authorize` runs before anything is preloaded, and that ordering is the point rather than a
  # style. Spelled the other way — one `find_by!` carrying the payload's `includes` — an existing
  # private deck paid every preload and was then refused, while an unknown key paid one query and
  # was refused identically: measured at 1 query / 3.2 ms for an unknown key against 2 for an empty
  # private deck and 3 / 8.6 ms for a 60-card one. The bodies are byte-identical, so what leaked
  # was the timing and the query count — existence, and the rough size of a deck somebody is not
  # allowed to read. DecksController#show already makes this call and says so in its own comment;
  # one extra primary-key SELECT is the price.
  def deck
    deck = Deck.find_by!(key: params[:id])
    authorize deck, :og_image?
    serve Og::DeckPayload.call(deck_for_payload(deck))
  end

  def archetype
    archetype = Archetype.find_by!(slug: params[:id])
    authorize archetype, :og_image?
    serve Og::ArchetypePayload.call(
      Archetype.preload(:primary_card, :secondary_card).find(archetype.id)
    )
  end

  def card
    card = Card.find(params[:id])
    authorize card, :og_image?
    serve Og::CardPayload.call(card)
  end

  private

  # `params[:v]` is deliberately never read. It is a cache-buster for the chat clients that key a
  # preview on the image's URL, not a lookup key — and the difference is the whole behaviour: a
  # client that cached `?v=<old>` re-requests exactly that URL, and Og::Cache has by then deleted
  # the old file. Keying on it would answer 404, so every preview would break precisely once, at
  # the moment its subject changed, for every client that had already seen it. Ignoring it means a
  # stale URL renders the current banner, which is what a cache-buster is supposed to do.
  #
  # `immutable` is honest here for the same reason: this URL's bytes really never change, because
  # a change produces a different URL.
  def serve(payload)
    expires_in 1.year, public: true, immutable: true
    send_data Og::Cache.fetch(payload), type: "image/jpeg", disposition: "inline"
  end

  # with_standard_pool because the payload's subtitle names the pool through Deck#format_label,
  # and StandardPool#name reads *both* of its bounds — that scope exists so this is one preload
  # rather than three queries, and CLAUDE.md names it as the one place the spelling should live.
  def deck_for_payload(deck)
    Deck.with_standard_pool
        .includes(archetype: [ :primary_card, :secondary_card ], deck_cards: { card: :pokemon_subtype })
        .find(deck.id)
  end
end
