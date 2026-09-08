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

  rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
    name: "og-image", unless: -> { user_signed_in? },
    store: RateLimitStore, only: [ :deck, :archetype, :card ]

  # A refusal answers 404 and needs no code: PubliclyReachable's `included do` already routes both
  # RecordNotFound and Pundit::NotAuthorizedError onto the static 404, so an unknown key and a
  # private deck are indistinguishable. Note that this controller must *not* copy
  # DecksController's override of #not_found, which redirects a session-less requester to the
  # sign-in page — right for a page a human typed, wrong for an image a crawler asked for.
  def deck
    deck = Deck.includes(archetype: [ :primary_card, :secondary_card ],
                         deck_cards: { card: :pokemon_subtype }).find_by!(key: params[:id])
    authorize deck, :og_image?
    serve Og::DeckPayload.call(deck)
  end

  def archetype
    archetype = Archetype.preload(:primary_card, :secondary_card).find_by!(slug: params[:id])
    authorize archetype, :og_image?
    serve Og::ArchetypePayload.call(archetype)
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
    send_file Og::Cache.fetch(payload), type: "image/jpeg", disposition: "inline"
  end
end
