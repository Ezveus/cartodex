class PokemonSubtype < ApplicationRecord
  has_many :cards

  validates :name, presence: true, uniqueness: true

  # Which rule box a card's name declares. This lives on the model rather than inside the one
  # importer that used to own it because there are now two writers — `Cards::Fetcher` for
  # Limitless and `Cards::OfficialImporter` for the official card database — and a second copy of
  # a classification rule is a copy that drifts. It is read, not merely displayed:
  # `Decks::ArchetypeDetector` weights a member with a rule box at 3 instead of 2, so a name this
  # method fails to recognise quietly re-ranks every archetype built on that card.
  #
  # Order matters. "Mega ... ex" has to be tested before the bare " ex" suffix it ends with, and
  # " ex" and " EX" name genuinely different cards rather than two spellings of one — folding
  # their case here would merge two rule boxes with different prize counts.
  def self.for_card_name(name)
    return nil if name.blank?

    subtype =
      if name.include?("Mega ") && name.end_with?(" ex") then "Mega Evolution ex"
      elsif name.end_with?(" ex") then "Pokémon ex"
      elsif name.end_with?(" EX") then "Pokémon EX"
      elsif name.include?("VMAX") then "Pokémon VMAX"
      elsif name.include?("VSTAR") then "Pokémon VSTAR"
      elsif name.include?("V-UNION") then "Pokémon V-UNION"
      elsif name.match?(/ V\z/) then "Pokémon V"
      end

    find_by(name: subtype) if subtype
  end
end
