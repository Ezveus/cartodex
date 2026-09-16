namespace :official_cards do
  desc "Import cards from fragments captured by bin/scrape_official_cards (dir, slug, set code, set name)"
  task :import, [ :dir, :slug, :set_code, :set_name ] => :environment do |_t, args|
    abort "usage: official_cards:import[dir,slug,SET_CODE,Set Name]" if args[:dir].blank? ||
      args[:slug].blank? || args[:set_code].blank?

    result = Cards::OfficialImporter.call(
      dir: args[:dir], slug: args[:slug],
      set_code: args[:set_code], set_full_name: args[:set_name]
    )

    puts "Imported #{result.imported} card(s), skipped #{result.skipped} already in the catalogue."

    if result.failed.any?
      puts "\n#{result.failed.size} failed:"
      result.failed.each { |path, message| puts "  #{File.basename(path)} — #{message}" }
      puts "\nThese are not retried automatically. Re-run after fixing, or capture them again."
      exit 1
    end
  end

  desc "Move a set's cards and its set row onto another code, for when Limitless publishes its own"
  task :rename_set, [ :from, :to ] => :environment do |_t, args|
    from, to = args[:from].to_s.strip, args[:to].to_s.strip
    abort "usage: official_cards:rename_set[FROM,TO]" if from.blank? || to.blank?

    # Keyed on cards.set_name, never on card_sets.code: the catalogue holds 54 codes in the
    # column against 28 rows in the table, so a target that exists only as a set_name would pass
    # a code-only check and then collide with index_cards_on_set_name_and_set_number, part-way
    # through, with the set row already moved.
    if Card.exists?(set_name: to) || CardSet.exists?(code: to)
      puts "#{to} is already in use — #{Card.where(set_name: to).count} card(s) carry it."
      puts "Nothing was moved."
      exit 1
    end

    moved = 0
    ActiveRecord::Base.transaction do
      moved = Card.where(set_name: from).update_all(set_name: to)
      CardSet.where(code: from).update_all(code: to)
    end

    puts "Moved #{moved} card(s) from #{from} to #{to}."
    puts "CardSets::RescrapeJob will now look them up at limitlesstcg.com/cards/#{to}/<number>."
  end
end
