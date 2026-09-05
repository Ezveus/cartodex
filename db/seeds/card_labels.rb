# A bootstrap, not the source of truth. bin/docker-entrypoint runs db:seed before the server
# accepts traffic on every deploy, and labels are maintained from the admin panel — so this file
# adds a slug it does not find and never rewrites one it does, exactly like
# db/seeds/standard_pools.rb. Reasserting the values here would silently revert an admin's
# correction on the next deploy.
#
# Stage 2 grows a second loop over CardLabel::ROLES for the `role` family.
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
