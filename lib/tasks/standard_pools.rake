namespace :standard_pools do
  desc "Anchor Standard decks and tournaments that predate the standard_pool column"
  task backfill_anchors: :environment do
    result = StandardPools::AnchorBackfill.call

    puts "Anchored #{result.decks} deck(s) and #{result.tournaments} tournament(s)."

    if result.approximated.any?
      puts "\n#{result.approximated.size} tournament(s) predate every seeded pool and were"
      puts "anchored to the oldest one. A re-run will not revisit them — fix these by hand:"
      result.approximated.each { |tournament| puts "  #{tournament}" }
    end

    if result.skipped.any?
      puts "\nSkipped:"
      result.skipped.each { |reason| puts "  #{reason}" }
      exit 1
    end
  end
end
