# The Standard calendar. One row per pool-creating event since the 2025 rotation:
# a set release moves the upper bound, a rotation moves the lower bound. Two sets
# released the same day are one event and one pool, named the way Limitless names
# it (SVI-BLK, not SVI-BLK/WHT), which also covers the energy subsets SVE and MEE.
#
# Earlier rotations are absent on purpose: their lower bound is a Sword & Shield
# set, and no Sword & Shield set exists in card_sets — seeding them would mean
# inventing set rows to hang them off.
#
# This file is a bootstrap, not the source of truth: pools are maintained from the
# admin panel. It is keyed on the bound pair, which the unique index guarantees,
# so re-running it after admin edits neither duplicates nor overwrites.
#
# legal_on is Play! Pokémon tournament legality, which is usually the second
# Friday after the US release (release + 14) but is NOT a formula — see ASC below.
# It is stored rather than computed precisely because of that.
#
# The J mark starts at ASC, not at MEG: the Mega Evolution block opens on I
# (Mega Lucario ex is MEG 77, mark I), so MEG and PFL add no new mark.
POOLS = [
  { first: "SVI", last: "JTG", marks: %w[G H I],   released_on: "2025-04-11", legal_on: "2025-04-11" },
  { first: "SVI", last: "DRI", marks: %w[G H I],   released_on: "2025-05-30", legal_on: "2025-06-13" },
  { first: "SVI", last: "BLK", marks: %w[G H I],   released_on: "2025-07-18", legal_on: "2025-08-01" },
  { first: "SVI", last: "MEG", marks: %w[G H I],   released_on: "2025-09-26", legal_on: "2025-10-10" },
  { first: "SVI", last: "PFL", marks: %w[G H I],   released_on: "2025-11-14", legal_on: "2025-11-28" },
  # ASC shipped staggered — the ETB only arrived 2026-02-20 — so Play! Pokémon
  # pushed its legality to 2026-03-06, past the 2026-02-13 EUIC. Five weeks after
  # release, not two: do not "fix" this back to the +14 rule.
  { first: "SVI", last: "ASC", marks: %w[G H I J], released_on: "2026-01-30", legal_on: "2026-03-06" },
  { first: "TEF", last: "POR", marks: %w[H I J],   released_on: "2026-03-27", legal_on: "2026-04-10" },
  { first: "TEF", last: "CRI", marks: %w[H I J],   released_on: "2026-05-22", legal_on: "2026-06-05" },
  { first: "TEF", last: "PBL", marks: %w[H I J],   released_on: "2026-07-17", legal_on: "2026-07-31" }
].freeze

missing = []

POOLS.each do |attrs|
  first_set = CardSet.find_by(code: attrs[:first])
  last_set  = CardSet.find_by(code: attrs[:last])

  # A pool whose bounds are not in the database cannot be written: both columns
  # are NOT NULL. Report it rather than aborting the run part-way.
  if first_set.nil? || last_set.nil?
    missing << "#{attrs[:first]}-#{attrs[:last]}"
    next
  end

  pool = StandardPool.find_or_initialize_by(first_card_set: first_set, last_card_set: last_set)
  pool.regulation_marks = attrs[:marks]
  pool.released_on = attrs[:released_on]
  pool.legal_on = attrs[:legal_on]
  pool.save!
end

puts "Seeded #{StandardPool.count} Standard pools; current is #{StandardPool.current&.name || 'none'}"
puts "Skipped (bound set missing): #{missing.join(', ')}" if missing.any?
