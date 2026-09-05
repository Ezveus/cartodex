module Archetypes
  # Who the archetype is: the printings that name it, and where it sits in the archetype tree.
  #
  # This is the first surface in the app where an archetype carries an image at all. The art goes
  # through the image proxy (`image_card_path`, CardsController#image) and never through the
  # scraped `image_url`, so the page makes no third-party request of its own — and it is rendered
  # only when there *is* an `image_url`, because the proxy has nothing to fetch without one and
  # would answer a broken image for every archetype whose lead card was imported before art was
  # scraped.
  class Identity < ApplicationComponent
    def initialize(archetype:)
      @archetype = archetype
    end

    def view_template
      return if member_cards.empty? && lineage_parts.empty?

      div(class: "archetype-identity") do
        art
        lineage
      end
    end

    private

    def member_cards
      @member_cards ||= [ @archetype.primary_card, @archetype.secondary_card ].compact
    end

    def art
      illustrated = member_cards.select { |card| card.image_url.present? }
      return if illustrated.empty?

      div(class: "archetype-art") do
        illustrated.each do |card|
          link_to card_path(card), class: "archetype-art-item" do
            image_tag image_card_path(card), alt: card.name, loading: "lazy", class: "archetype-art-image"
            span(class: "archetype-art-label") { card.printing_label }
          end
        end
      end
    end

    # Parent and children are rendered as links to their own pages: a variant's report is a
    # different sample, not a subset of this one, and the hierarchy is the only thing that says
    # the two are related at all.
    def lineage_parts
      @lineage_parts ||= begin
        parts = []
        parts << [ "Variant of ", [ @archetype.parent ] ] if @archetype.parent
        children = @archetype.children.sort_by(&:name)
        parts << [ "Variants: ", children ] if children.any?
        parts
      end
    end

    def lineage
      return if lineage_parts.empty?

      p(class: "archetype-lineage") do
        lineage_parts.each do |label, archetypes|
          span(class: "archetype-lineage-part") do
            plain label
            archetypes.each_with_index do |archetype, index|
              plain ", " if index.positive?
              link_to archetype.name, archetype_path(archetype)
            end
          end
        end
      end
    end
  end
end
