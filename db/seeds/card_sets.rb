# Seed card sets with block and release date information
SETS = [
  # Scarlet & Violet block
  { code: "SVI", name: "Scarlet & Violet",        block_name: "Scarlet & Violet", release_date: "2023-03-31" },
  { code: "SVE", name: "Scarlet & Violet Energy",  block_name: "Scarlet & Violet", release_date: "2023-03-31" },
  { code: "PAL", name: "Paldea Evolved",            block_name: "Scarlet & Violet", release_date: "2023-06-09" },
  { code: "TEF", name: "Temporal Forces",            block_name: "Scarlet & Violet", release_date: "2024-03-22" },
  { code: "TWM", name: "Twilight Masquerade",        block_name: "Scarlet & Violet", release_date: "2024-05-24" },
  { code: "SFA", name: "Shrouded Fable",             block_name: "Scarlet & Violet", release_date: "2024-08-02" },
  { code: "SCR", name: "Stellar Crown",              block_name: "Scarlet & Violet", release_date: "2024-09-13" },
  { code: "SSP", name: "Surging Sparks",             block_name: "Scarlet & Violet", release_date: "2024-11-08" },
  { code: "PRE", name: "Prismatic Evolutions",       block_name: "Scarlet & Violet", release_date: "2025-01-17" },
  { code: "JTG", name: "Journey Together",            block_name: "Scarlet & Violet", release_date: "2025-03-28" },
  { code: "DRI", name: "Destined Rivals",             block_name: "Scarlet & Violet", release_date: "2025-05-30" },
  { code: "BLK", name: "Black Bolt",                  block_name: "Scarlet & Violet", release_date: "2025-07-18" },
  { code: "WHT", name: "White Flare",                 block_name: "Scarlet & Violet", release_date: "2025-07-18" },

  # Mega Evolution block
  { code: "MEG", name: "Mega Evolution",              block_name: "Mega Evolution", release_date: "2025-09-26" },
  { code: "MEE", name: "Mega Evolution Energy",       block_name: "Mega Evolution", release_date: "2025-09-26" },
  { code: "PFL", name: "Phantasmal Flames",            block_name: "Mega Evolution", release_date: "2025-11-14" },
  { code: "ASC", name: "Ascended Heroes",             block_name: "Mega Evolution", release_date: "2026-01-30" },
  { code: "POR", name: "Perfect Order",               block_name: "Mega Evolution", release_date: "2026-03-27" },
  { code: "CRI", name: "Chaos Rising", block_name: "Mega Evolution", release_date: "2026-05-22" }
].freeze

SETS.each do |attrs|
  card_set = CardSet.find_or_initialize_by(code: attrs[:code])
  card_set.update!(attrs)
end

# Link existing cards to their sets
Card.where(card_set_id: nil).find_each do |card|
  card_set = CardSet.find_by(code: card.set_name)
  card.update_column(:card_set_id, card_set.id) if card_set
end

puts "Seeded #{CardSet.count} card sets, linked #{Card.where.not(card_set_id: nil).count} cards"
