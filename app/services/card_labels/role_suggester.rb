module CardLabels
  # Proposes a card's roles from the text the catalogue already holds, and never decides one.
  #
  # Measured on the production dump (4723 cards, 3023 fingerprints) on 2026-09-06: the rules below
  # label 33 of the 51 Trainer/Energy fingerprints the 107 recorded lists play and 13 of the 43
  # Pokémon ones — 689 fingerprints and 714 assignments over the whole catalogue, in 1.2 s. They
  # also hand *Telepathic Psychic Energy* a `search` role it does not deserve, and say nothing at
  # all about Pokégear 3.0, Explorer's Guidance, Bug Catching Set or Professor Turo's Scenario,
  # which are among the first cards a player would name. Coverage is not the problem: an error
  # this service makes is invisible on the rendered report, which is why a human decides and this
  # only saves them typing.
  #
  # The three provenance rules, in one sentence each:
  #
  # * it writes `suggested` rows and no others;
  # * a pair already carrying a `curated` decision — a yes *or* a refusal — is not examined at
  #   all, so a re-run six weeks later cannot undo a human;
  # * a `suggested` row no rule still matches is **deleted**. That is the one deletion in this
  #   feature, and it deletes only the machine's own opinion: leaving it would show the curation
  #   screen a proposal nothing proposes any more.
  class RoleSuggester < ApplicationService
    class MissingRoles < StandardError; end

    Result = Struct.new(
      :created, :kept, :withdrawn, :decided, :unfingerprinted, :fingerprints_examined,
      keyword_init: true
    )

    # One rule per slug in CardLabel::ROLES, and the keys are asserted equal to it by a test —
    # a rule naming a role the vocabulary does not hold could never be written, and a role no rule
    # names is a checkbox only a human can ever tick.
    #
    # Each rule is one line, however long, and never /x: extended mode ignores literal whitespace,
    # so the multi-line form of three of these silently stopped matching anything — measured on the
    # production dump, gust, recovery and energy-acceleration wrote 0 rows where they should have
    # written 34, 45 and 58, and every test still passed. The per-rule test below is what would
    # have caught it.
    #
    # No rule reads a card's *name*. A rule that named Iono would be curation wearing a rule's
    # clothes: it would be right about exactly one card and would say nothing about the next set.
    RULES = {
      "draw" => /\bdraws?\b[^.]{0,60}\bcards?\b|\bdraw a card\b/i,
      "search" => /search your deck/i,
      "gust" => /switch(?: in)? \d+ of your opponent's benched|your opponent's benched pok[eé]mon (?:with their active|to the active spot)/i,
      "switch" => /switch your active pok[eé]mon with \d+ of your benched/i,
      "recovery" => /from your discard pile into your hand|from your discard pile into your deck|shuffle[^.]{0,40}from your discard pile/i,
      "disruption" => /your opponent (?:shuffles|discards)|each player shuffles their hand|opponent's hand/i,
      "energy-acceleration" => /attach[^.]{0,80}energy[^.]{0,40}from your (?:discard pile|deck)|attach[^.]{0,40}from your discard pile to/i
    }.freeze

    def call
      labels = role_labels
      @created = @kept = @withdrawn = @decided = 0

      # Read the whole catalogue *before* opening the transaction, the same discipline
      # Tournaments::StandingsImporter follows for its card fetches. serialized_transaction is a
      # SQLite BEGIN IMMEDIATE, so it takes the database's single write lock for its whole
      # duration — and measured on the production dump the reading half (4723 cards with their
      # attacks and abilities, then seven regex passes over 3023 fingerprints) is 0.4 s of a 1.2 s
      # run. Inside the transaction that is 0.4 s in which every other writer waits, against
      # database.yml's 5 s busy timeout, for a service that is only looking.
      matches = matches_by_fingerprint

      serialized_transaction do
        RULES.each_key { |slug| apply(labels.fetch(slug), matches) }
        labels.except(*RULES.keys).each_value { |orphan| abandon(orphan) }
      end

      Result.new(
        created: @created, kept: @kept, withdrawn: @withdrawn, decided: @decided,
        unfingerprinted: unfingerprinted.size, fingerprints_examined: printings_by_fingerprint.size
      )
    end

    private

    # Refuses before writing anything rather than skipping the rules whose row is missing: a run
    # that wrote four of the seven families would leave a report that looks complete and is not,
    # and the vocabulary is seeded before the server accepts traffic (bin/docker-entrypoint).
    def role_labels
      labels = CardLabel.roles.index_by(&:slug)
      missing = RULES.keys - labels.keys
      raise MissingRoles, "no card_labels row for #{missing.to_sentence} — run db:seed" if missing.any?

      labels
    end

    # A role can only lose its rule through a code change — the seed never deletes and
    # Admin::CardLabelsController refuses to destroy a `role` label — and the row then survives
    # with its assignments. The human's decisions on it are theirs to keep; its `suggested` rows
    # are the machine's, and nothing will ever withdraw them again, so they go now rather than
    # standing behind a report section built on guesses no rule still makes.
    def abandon(label)
      stale = label.assignments.suggested
      @withdrawn += stale.count
      stale.delete_all
    end

    def apply(label, matches)
      existing = label.assignments.index_by(&:fingerprint)
      wanted = matches.fetch(label.slug, Set.new)

      wanted.each do |fingerprint|
        assignment = existing[fingerprint]
        next @decided += 1 if assignment && assignment.source != "suggested"
        next @kept += 1 if assignment

        label.assignments.create!(fingerprint: fingerprint, source: "suggested",
                                  card: printings_by_fingerprint.fetch(fingerprint).last)
        @created += 1
      end

      withdraw(label, existing, wanted)
    end

    def withdraw(label, existing, wanted)
      stale = existing.values.select { |assignment| assignment.source == "suggested" }
                      .reject { |assignment| wanted.include?(assignment.fingerprint) }

      @withdrawn += stale.size
      label.assignments.where(id: stale.map(&:id)).delete_all
    end

    # slug -> the fingerprints its rule matches.
    def matches_by_fingerprint
      RULES.each_with_object({}) do |(slug, rule), matches|
        matched = text_by_fingerprint.filter_map { |fingerprint, text| fingerprint if text.match?(rule) }
        matches[slug] = matched.to_set
      end
    end

    # The text of a *card*, which is the union of its printings' — a Trainer's fingerprint is a
    # hash of its name alone, so two printings can in principle carry differently worded text and
    # a reprint that clarified its wording would otherwise withdraw a role on the next run.
    # Measured on the production dump: 193 Trainer/Energy fingerprints hold several printings and
    # 0 of them disagree on `effect`, so this costs nothing today and is a hedge, not a fix.
    def text_by_fingerprint
      @text_by_fingerprint ||= printings_by_fingerprint.transform_values do |printings|
        printings.flat_map { |card| card_text(card) }.join(" ")
      end
    end

    def card_text(card)
      parts = [ card.effect.to_s ]
      card.attacks.each { |attack| parts << attack.name.to_s << attack.effect.to_s }
      card.abilities.each { |ability| parts << ability.name.to_s << ability.effect.to_s }
      parts.join(" ")
    end

    # Ordered by id, so `.last` is the printing the catalogue learned about most recently — the
    # only claim this pointer makes. It is where the decision was read from and what
    # card_labels:resync_fingerprints re-derives a moved fingerprint from; the report never joins
    # on it.
    def printings_by_fingerprint
      @printings_by_fingerprint ||= fingerprinted.group_by(&:fingerprint)
    end

    def fingerprinted
      load_cards
      @fingerprinted
    end

    def unfingerprinted
      load_cards
      @unfingerprinted
    end

    def load_cards
      return if defined?(@fingerprinted)

      all = Card.includes(:attacks, :abilities).order(:id).to_a
      @unfingerprinted, @fingerprinted = all.partition { |card| card.fingerprint.blank? }
    end
  end
end
