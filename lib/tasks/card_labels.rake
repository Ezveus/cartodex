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

  # Propose roles from the card text, for every card in the catalogue. Safe to re-run: it writes
  # only its own `suggested` rows, never examines a pair a human has decided, and withdraws the
  # suggestions its own rules no longer make.
  #
  # It does not abort on anything it reports, unlike resync_fingerprints above: nothing here is
  # ambiguous — a card the rules say nothing about is simply a card nobody has curated yet, which
  # is the state /admin/card_roles exists to work through, and failing a boot on it would be
  # failing a boot on curation debt.
  desc "Suggest card roles from the effect, attack and ability text the catalogue already holds"
  task suggest_roles: :environment do
    result = CardLabels::RoleSuggester.call

    puts "Examined #{result.fingerprints_examined} #{"card".pluralize(result.fingerprints_examined)}."
    puts "Created #{result.created}, kept #{result.kept}, withdrew #{result.withdrawn}."
    puts "Left #{result.decided} decided by hand untouched."
    # `next`, not `return`: a rake task body is a block, and `return` out of one raises
    # LocalJumpError — which the fixtures hide, since they always leave a few unfingerprinted
    # printings and the branch is never taken in a test.
    next if result.unfingerprinted.zero?

    puts "Skipped #{result.unfingerprinted} printings with no fingerprint, which cannot be labelled."
  end
end
