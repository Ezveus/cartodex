namespace :standard_pools do
  desc "Anchor Standard decks and tournaments that predate the standard_pool column"
  task backfill_anchors: :environment do
    result = StandardPools::AnchorBackfill.call

    puts "Anchored #{result.decks} deck(s) and #{result.tournaments} tournament(s)."

    if result.skipped.any?
      puts "\nNothing was written:"
      result.skipped.each { |reason| puts "  #{reason}" }
      exit 1
    end
  end
end
