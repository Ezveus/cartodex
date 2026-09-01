# Seed card sets with block and release date information
SETS = [
  # Scarlet & Violet block
  { code: "SVI", name: "Scarlet & Violet",        block_name: "Scarlet & Violet", release_date: "2023-03-31" },
  { code: "SVE", name: "Scarlet & Violet Energy",  block_name: "Scarlet & Violet", release_date: "2023-03-31" },
  { code: "PAL", name: "Paldea Evolved",            block_name: "Scarlet & Violet", release_date: "2023-06-09" },
  { code: "OBF", name: "Obsidian Flames",           block_name: "Scarlet & Violet", release_date: "2023-08-11" },
  { code: "MEW", name: "151",                        block_name: "Scarlet & Violet", release_date: "2023-09-22" },
  { code: "PAR", name: "Paradox Rift",               block_name: "Scarlet & Violet", release_date: "2023-11-03" },
  { code: "PAF", name: "Paldean Fates",              block_name: "Scarlet & Violet", release_date: "2024-01-26" },
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
  { code: "CRI", name: "Chaos Rising", block_name: "Mega Evolution", release_date: "2026-05-22" },
  { code: "PBL", name: "Pitch Black",                 block_name: "Mega Evolution", release_date: "2026-07-17" }
].freeze

# Fills what is missing and overwrites nothing — the same `||=` guard CardSets::Importer
# uses, and for the same reason. This seed used to `update!` unconditionally, so every run
# reasserted the hardcoded name, block and release date over whatever was in the database,
# reverting any correction made from the admin panel. That is what kept db:seed off the
# deploy path; it now runs on every boot, so it must not fight the admin screen.
#
# Scoped by region as well as code: card_sets is UNIQUE on (region, code), not on code, so a
# bare code lookup would find a Japanese set of the same code once #111 lands and rewrite it
# with international data.
created = 0
filled = 0

SETS.each do |attrs|
  card_set = CardSet.find_or_initialize_by(code: attrs[:code], region: "international")
  was_new = card_set.new_record?

  card_set.name ||= attrs[:name]
  card_set.block_name ||= attrs[:block_name]
  card_set.release_date ||= attrs[:release_date]

  next unless card_set.changed?

  card_set.save!
  was_new ? created += 1 : filled += 1
end

# Link existing cards to their sets
Card.where(card_set_id: nil).find_each do |card|
  card_set = CardSet.find_by(code: card.set_name)
  card.update_column(:card_set_id, card_set.id) if card_set
end

puts "Card sets: #{created} created, #{filled} completed, #{CardSet.count} total; " \
     "#{Card.where.not(card_set_id: nil).count} cards linked"
