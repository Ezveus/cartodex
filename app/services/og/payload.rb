module Og
  # LAYOUT_VERSION and MAX_ARTS live in app/services/og.rb, the explicit namespace file, so that
  # reading either one loads them. Declared here they were invisible to any caller that had not
  # already touched this class — see the comment there.
  #
  # What one banner says, decided entirely from the record: Og::Renderer takes one of these and
  # draws it, Og::Cache addresses a file by its kind, key and digest, and Ui::OgTags prints it.
  # All the product knowledge lives in the four builders beside this file and none of the drawing
  # does.
  #
  #   kind      "site" | "deck" | "archetype" | "card" — a String, never a Symbol, because it
  #             reaches Phlex as an attribute *value* and Phlex dasherizes those.
  #   key       the segment the subject is already addressed by: decks.key, archetypes.slug,
  #             cards.id. nil for "site".
  #   title     never blank. subtitle: a String or nil.
  #   art_urls  0 to MAX_ARTS non-blank remote card image_urls.
  #   digest    16 hex characters; nil only for "site".
  Payload = Struct.new(:kind, :key, :title, :subtitle, :art_urls, :digest, keyword_init: true) do
    # Called at the end of every builder, because Struct.new(keyword_init: true) raises
    # ArgumentError on an *extra* keyword but stores nil for a *missing* one (measured; the same
    # trap is written down at app/views/components/styleguide/page_view.rb:394). A builder that
    # forgot `digest:` would otherwise hand Og::Cache a path of `…/key-.jpg` and the page an
    # empty `?v=`, with nothing raising anywhere.
    def validate!
      raise ArgumentError, "an og payload needs a kind" if kind.blank?
      raise ArgumentError, "an og payload needs a title" if title.blank?
      raise ArgumentError, "a #{kind} og payload needs a digest" if kind != "site" && digest.blank?
      # The contract says 0 to MAX_ARTS and every builder enforces it with `.first(MAX_ARTS)`, so
      # this guards the contract rather than the builders: a fifth caller written later, or a
      # payload hand-built in a test, would otherwise hand Og::Renderer more arts than the layout
      # has positions for.
      if Array(art_urls).size > MAX_ARTS
        raise ArgumentError, "an og payload draws at most #{MAX_ARTS} arts, got #{art_urls.size}"
      end

      self
    end

    # The digest format, in one place: three builders compute one, Og::Cache names a file after
    # it and every page carrying a preview repeats it as `?v=`. 16 hex characters of SHA-256 over
    # the parts joined by an ASCII unit separator — a character no card name, deck name or URL
    # contains, so two different part lists cannot join to the same string.
    #
    # `join` stringifies, so a nil part (a deck holding no cards has no newest deck-card
    # timestamp) becomes an empty field rather than an exception, deterministically.
    #
    # One place, called as `Payload.digest_of([ Og::LAYOUT_VERSION, … ])`: three builders compute
    # a digest, and three copies of a format that appears in every preview URL in the app is
    # exactly the kind of thing that drifts by one term.
    def self.digest_of(parts)
      ::Digest::SHA256.hexdigest(parts.join("\x1f")).first(DIGEST_LENGTH)
    end
  end
end
