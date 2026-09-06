# A bootstrap, not the source of truth. bin/docker-entrypoint runs db:seed before the server
# accepts traffic on every deploy, and labels are maintained from the admin panel — so this file
# adds a slug it does not find and never rewrites one it does, exactly like
# db/seeds/standard_pools.rb. Reasserting the values here would silently revert an admin's
# correction on the next deploy.
#
# The two families are seeded from two places on purpose: a `type` label is data, so its list
# lives here and an admin may add to it; a `role` label is referenced by code, so its list is
# CardLabel::ROLES and this file only walks it.
#
# Local variable instead of constant: this file is loaded twice in one test process
# (CardLabelSeedTest loads it twice), which would re-initialize a constant and print a warning.
type_labels = [
  {
    slug: "ace-spec",
    name: "ACE SPEC",
    position: 10,
    source_query: "is:ace",
    description: "A deck may hold at most one. Nothing in a scraped card page says so — the flag " \
                 "comes from Limitless's card search, which is the only source that carries it."
  }
].freeze

type_labels.each do |attributes|
  next if CardLabel.exists?(slug: attributes[:slug])

  CardLabel.create!(family: "type", **attributes)
  puts "Created card label #{attributes[:slug]}"
end

CardLabel::ROLES.each do |attributes|
  next if CardLabel.exists?(slug: attributes[:slug])

  CardLabel.create!(family: "role", **attributes)
  puts "Created card label #{attributes[:slug]}"
end
