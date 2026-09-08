module Ui
  # The Open Graph and Twitter card tags. Rendered on every page by
  # Layouts::ApplicationLayout, from whatever Og::Payload OgPreviewHost hands over — the site
  # default unless the action assigned its own.
  #
  # Every attribute value is a String, deliberately. Phlex dasherizes a Symbol passed as an
  # attribute *value* the same way it dasherizes a Symbol key, so `content: :website` would emit
  # `content="website"` today and something else the moment a value contains an underscore. The
  # numbers are quoted for the same reason: what a crawler parses is text.
  #
  # og:* uses `property` and twitter:* uses `name`. That is not a style choice — Open Graph is
  # RDFa, where the attribute is `property`, while the Twitter card spec reads `name`; a crawler
  # looking for one does not find the other.
  class OgTags < ApplicationComponent
    IMAGE_WIDTH = "1200".freeze
    IMAGE_HEIGHT = "630".freeze
    SITE_IMAGE = "og-default.jpg".freeze

    def initialize(payload:)
      @payload = payload
    end

    def view_template
      meta(property: "og:site_name", content: "Cartodex")
      meta(property: "og:type", content: site? ? "website" : "article")
      meta(property: "og:title", content: @payload.title)
      meta(property: "og:description", content: @payload.subtitle) if @payload.subtitle.present?
      # Omitted for the site payload rather than pointed at the root: a canonical URL of "/" on
      # /settings would be a claim about the page that is simply false, and a crawler that reads
      # no og:url falls back to the URL it fetched, which is right every time.
      meta(property: "og:url", content: canonical_url) unless site?

      meta(property: "og:image", content: image_url)
      meta(property: "og:image:type", content: "image/jpeg")
      meta(property: "og:image:width", content: IMAGE_WIDTH)
      meta(property: "og:image:height", content: IMAGE_HEIGHT)

      meta(name: "twitter:card", content: "summary_large_image")
      meta(name: "twitter:title", content: @payload.title)
      meta(name: "twitter:description", content: @payload.subtitle) if @payload.subtitle.present?
      meta(name: "twitter:image", content: image_url)
    end

    private

    def site? = @payload.kind == "site"

    # The digest rides in the URL because chat clients cache a preview keyed on the image's
    # address; a subject whose banner changed therefore has a new one. The endpoint itself never
    # reads it — see OgImagesController#serve.
    def image_url
      case @payload.kind
      when "site"      then URI.join(root_url, SITE_IMAGE).to_s
      when "deck"      then deck_og_image_url(@payload.key, v: @payload.digest)
      when "archetype" then archetype_og_image_url(@payload.key, v: @payload.digest)
      when "card"      then card_og_image_url(@payload.key, v: @payload.digest)
      else raise ArgumentError, "unknown Og::Payload kind #{@payload.kind.inspect}"
      end
    end

    def canonical_url
      case @payload.kind
      when "deck"      then deck_url(@payload.key)
      when "archetype" then archetype_url(@payload.key)
      when "card"      then card_url(@payload.key)
      end
    end
  end
end
