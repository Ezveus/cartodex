namespace :archetypes do
  desc "Recompute the denormalised fingerprint pair on every archetype and report collisions"
  task resync_fingerprints: :environment do
    result = Archetypes::FingerprintSync.call

    puts "Resynced #{result.updated} archetype(s)."

    if result.unfingerprinted.any?
      puts "\n#{result.unfingerprinted.size} archetype(s) point at a card that has never been scraped and were left alone:"
      result.unfingerprinted.each { |a| puts "  ##{a.id} #{a.name} (#{a.primary_card&.name})" }
      puts "\nRescrape those cards (admin panel, force: true) and run this again."
    end

    if result.collisions.any?
      puts "\n#{result.collisions.size} archetype(s) would collide once resynced and were left alone:"
      result.collisions.each { |a| puts "  ##{a.id} #{a.name} (#{a.primary_card&.name})" }
      puts "\nMerge them by hand — decks and deck results point at these rows."
    end

    exit 1 if result.collisions.any? || result.unfingerprinted.any?
  end
end
