namespace :card_labels do
  # Repair assignments whose fingerprint has moved under them.
  #
  # A force: true rescrape rewrites a card's fingerprint, and an assignment keyed on the old one
  # then joins to nothing: the card silently loses its label. This is why the assignment keeps the
  # printing it was decided from beside the fingerprint — the same pair, for the same reason, as
  # Archetype's primary_card_id / primary_fingerprint.
  #
  # It reports rather than writes wherever the answer is ambiguous, exactly like
  # Archetypes::FingerprintSync: an assignment with no card left to read, and a move that would
  # collide with a decision already recorded for the target fingerprint. Writing either would abort
  # a run part way through and leave the rest unexamined.
  desc "Move card label assignments onto their card's current fingerprint, reporting what it cannot"
  task resync_fingerprints: :environment do
    reports = []
    moved = 0

    # Both associations, not :card alone: every report line below reads assignment.card_label.slug,
    # and preloading only the one this task writes through would N+1 the other on every line.
    CardLabelAssignment.includes(:card, :card_label).find_each do |assignment|
      next if Card.exists?(fingerprint: assignment.fingerprint)

      card = assignment.card
      if card.nil? || card.fingerprint.blank?
        reports << "#{assignment.card_label.slug}: #{assignment.fingerprint} matches no card, and " \
                   "the assignment names no printing to read one from"
        next
      end

      if CardLabelAssignment.exists?(card_label_id: assignment.card_label_id, fingerprint: card.fingerprint)
        reports << "#{assignment.card_label.slug}: #{assignment.fingerprint} moved to " \
                   "#{card.fingerprint}, which already carries a decision — resolve by hand"
        next
      end

      # update_column, not update!: shifting the key has no business asking whether the rest of the
      # row validates, the same call DecksController#share and #unclaim make.
      assignment.update_column(:fingerprint, card.fingerprint)
      moved += 1
    end

    puts "Moved #{moved} #{"assignment".pluralize(moved)}."
    next if reports.empty?

    puts "#{reports.size} could not be moved:"
    reports.each { |line| puts "  #{line}" }
    abort "card_labels:resync_fingerprints left #{reports.size} assignments unresolved."
  end
end
