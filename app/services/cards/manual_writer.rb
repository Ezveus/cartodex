module Cards
  # The admin panel's one writer of a card's text, for a card created from scratch and for an edit.
  #
  # It exists because `Card#compute_fingerprint` reads the attacks and abilities: a Pokémon has to
  # be saved once, with them built, or it takes the fingerprint of a card that has none and is
  # invisible to `Decks::ArchetypeDetector` and `Cards::Printings` for good. Slots are shaped the
  # way `Cards::Fetcher` shapes them, so a hand-made printing fingerprints like a scraped reprint.
  class ManualWriter < ApplicationService
    ATTACK_SLOTS = 3
    ABILITY_SLOTS = 2
    ATTACK_FIELDS = %w[name cost damage effect].freeze
    ABILITY_FIELDS = %w[name effect].freeze

    def initialize(card, attributes:, attacks:, abilities:)
      @card = card
      @attributes = attributes.to_h.transform_values { _1.is_a?(String) ? _1.strip : _1 }
      @attacks = attacks
      @abilities = abilities
    end

    def call
      attacks, attack_errors = kept_slots(@attacks, ATTACK_FIELDS, "Attack")
      abilities, ability_errors = kept_slots(@abilities, ABILITY_FIELDS, "Ability")
      written = false

      # Destroying the old slots commits on its own, so the replacement and the save share one
      # transaction: a refused card must find its previous attacks still there.
      serialized_transaction do
        assign(attacks, abilities)
        valid = @card.valid?
        (attack_errors + ability_errors).each { @card.errors.add(:base, _1) }
        raise ActiveRecord::Rollback unless valid && @card.errors.empty?

        @card.save!
        written = true
      end

      # After the transaction, not inside it: a reader refilling the cache from uncommitted rows
      # would pin the old values for the whole TTL.
      Card.forget_filter_values if written
      written
    end

    private

    def assign(attacks, abilities)
      @card.assign_attributes(@attributes)
      @card.pokemon_subtype = (PokemonSubtype.for_card_name(@card.name) if @card.card_type == "Pokémon")

      if @card.persisted?
        @card.attacks.destroy_all
        @card.abilities.destroy_all
        # `Og::CardPayload#digest` folds `updated_at` and the banner is served immutable, so an
        # edit touching only an attack's text must still move it.
        @card.updated_at = Time.current
      end

      attacks.each_with_index do |slot, position|
        @card.attacks.build(name: slot["name"], cost: slot["cost"].presence || "0",
                            damage: slot["damage"].presence, effect: slot["effect"].presence, position:)
      end
      abilities.each_with_index do |slot, position|
        @card.abilities.build(name: slot["name"], effect: slot["effect"].presence, position:)
      end
    end

    # A slot left entirely blank is an unused slot; one with text but no name is refused rather than
    # dropped, since dropping it would silently lose what the admin typed.
    def kept_slots(slots, fields, label)
      errors = []
      kept = slots.each_with_index.filter_map do |slot, index|
        values = fields.to_h { [ _1, slot[_1].to_s.strip ] }
        next if values.values.all?(&:empty?)
        if values["name"].empty?
          errors << "#{label} #{index + 1} needs a name"
          next
        end

        values
      end
      [ kept, errors ]
    end
  end
end
