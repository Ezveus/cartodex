# Proposes which cartodex Archetype a Limitless deck is, from one of its lists and its published
# name. It only ever **proposes**: an admin confirms the answer once per deck reference on the
# import preview, and LimitlessArchetypeMapping stores what they confirmed. A reference nobody has
# mapped blocks its rows by name; nothing here ever decides unattended.
#
# Three rules were measured against real lists off event 577 on 2026-09-22, and two were refused:
#
#   * The deck name matched against archetypes.name. Of 45 names, 4 match an archetype exactly, 5
#     have no plausible candidate, and token matching is wrong more often than right — `Greninja`
#     → *Mega Greninja ex / Dragapult ex*, `Mega Chandelure` → *Mega Froslass ex / Chandelure*.
#   * Decks::ArchetypeDetector alone. Over 56 sampled lists it matched 55, and 12 of those matches
#     are wrong: a rule-box tech card outscores the deck's own name card (`Slowking` filed as
#     *Lillie's Clefairy ex*), and genuine score ties are settled by whichever row the database
#     happened to return first, so one list lands under either of two archetypes on two runs.
#
# What ships is the third: **containment selects the candidates and the published name
# discriminates among them.** Containment is Decks::ArchetypeDetector.candidates, unchanged and not
# re-implemented — it answers "which archetypes are entirely present in this list", which is the
# right question, and a human chose those members. Only the ranking is new. Measured over 96 lists:
# 80 decided, 9 whose name says nothing (`Basic Box`, `Tera Box`), 4 ambiguous (`Dhelmise`, between
# Banette and Sinistcha), 3 with no candidate (`Marnie's Grimmsnarl`). One of the 80 is still wrong.
# A good proposer and a bad decider, which is exactly why it only proposes.
class Tournaments::ArchetypeProposer < ApplicationService
  # `suggested_cards` is what the preview's "+ New archetype" opens pre-filled with — at most two
  # Pokémon of the list, primary first. See #suggested_cards for why it is not the detector's own
  # suggestion.
  Proposal = Struct.new(:archetype, :verdict, :candidates, :suggested_cards, keyword_init: true) do
    def decided? = verdict == :decided
  end

  # Primary and secondary: an archetype has two member slots.
  MAX_SUGGESTED_CARDS = 2

  # `mega` and `ex` because cartodex spells a deck *Mega Lucario ex / Hariyama* where Limitless
  # spells it `Lucario Hariyama`: kept, they lend every Mega archetype an overlap against every
  # Mega deck name and the discriminator stops discriminating. `box` because `Basic Box`,
  # `Tera Box` and `Toxtricity Box` are Limitless's words for "no single deck name fits", which is
  # precisely the case that must come out :name_says_nothing — and cartodex has archetypes with
  # Box in their names for it to match against. `ex` is carried for the record rather than for
  # effect: MIN_TOKEN_LENGTH drops it first, so no test can tell it apart from its absence.
  STOP_WORDS = %w[mega ex box the and].freeze

  # Under three characters because `N's Zoroark` tokenises to `zoroark` either way, and a bare `n`
  # would match any archetype whose name contains a three-letter word starting with n.
  MIN_TOKEN_LENGTH = 3

  def initialize(list_text:, label:, archetypes:)
    @list_text = list_text.to_s
    @label = label.to_s
    @archetypes = archetypes
  end

  def call
    scored = Decks::ArchetypeDetector.candidates(fingerprints, archetypes: @archetypes)
    if scored.empty?
      return Proposal.new(archetype: nil, verdict: :no_candidate, candidates: [],
        suggested_cards: suggested_cards([]))
    end

    ranked = rank(scored)

    Proposal.new(archetype: archetype_for(ranked), verdict: verdict_for(ranked),
      candidates: ranked.map { |candidate| candidate[:archetype] },
      suggested_cards: suggested_cards(ranked.map { |candidate| candidate[:archetype] }))
  end

  private

  # [-overlap, -score, name]: the published name first, the containment score only as a tie-break,
  # and the name last so that the order is total and a run is reproducible. The score is read off
  # `candidates` rather than recomputed — a second table of weights is how the proposal and the
  # match come to disagree about one list.
  def rank(scored)
    scored
      .map { |archetype, score| { archetype: archetype, score: score, overlap: overlap(archetype) } }
      .sort_by { |candidate| [ -candidate[:overlap], -candidate[:score], candidate[:archetype].name.to_s ] }
  end

  # :decided needs a strict lead on overlap *and* score over the runner-up. Zero overlap is
  # answered before that comparison and not by it: a single candidate the name says nothing about
  # leads trivially, and `return :decided if candidates.one?` is the short-circuit that gets 9 of
  # the 96 measured rows wrong while passing every other case.
  def verdict_for(ranked)
    best, runner_up = ranked
    return :name_says_nothing if best[:overlap].zero?
    return :decided if runner_up.nil?
    return :ambiguous if [ best[:overlap], best[:score] ] == [ runner_up[:overlap], runner_up[:score] ]

    :decided
  end

  def archetype_for(ranked)
    ranked.first[:archetype] if verdict_for(ranked) == :decided
  end

  def overlap(archetype) = (tokens(@label) & tokens(archetype.name)).size

  def tokens(name)
    name.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").split
        .reject { |token| token.length < MIN_TOKEN_LENGTH || STOP_WORDS.include?(token) }
        .to_set
  end

  # Which cards a new archetype for this deck would be built from, read off the published name and
  # not off Decks::ArchetypeDetector#call's suggestion. Measured on event 578 (2026-09-30), that
  # suggestion — rule-box first, then HP — answers *Beedrill ex / Fezandipiti ex* for `Beedrill`
  # and puts *Cornerstone Mask Ogerpon ex* first for `Okidogi Barbaracle`: the rule-box tech
  # outscoring the deck's own card, which is the Slowking regression this class exists to avoid.
  #
  # Pokémon only — `basic` is a word of every Basic Energy's name, and `Basic Box` would otherwise
  # pre-fill *Basic Grass Energy*. A card is eligible only if it shares a token with what is left
  # of the name; the best covers the most of it, then comes earliest in it (cartodex names a pair
  # the way Limitless does, primary first), then is the most notable by the detector's own order.
  # The winner consumes every token it covers, so `Cynthia's Garchomp` does not go on to pick
  # *Cynthia's Gabite* for the leftover `cynthia`. A name matching nothing suggests nothing.
  #
  # The name gives the order only when no archetype has already given one: archetype identity is the
  # *ordered* fingerprint pair, and on event 578 `Clefairy Ogerpon` names the pair backwards from
  # the catalogue's *Teal Mask Ogerpon ex / Lillie's Clefairy ex* — "Create & select" on that line
  # made a reversed duplicate with a public page of its own. An existing candidate over exactly the
  # same cards therefore dictates the order, and the create answers with that archetype instead.
  def suggested_cards(candidates)
    aligned(picked_by_name, candidates)
  end

  def aligned(picked, candidates)
    # `to_s`: a card saved by a callback-bypassing write has no fingerprint, and nil does not sort.
    fingerprints = picked.map { |card| card.fingerprint.to_s }
    twin = candidates.find { |archetype|
      members = [ archetype.primary_card, archetype.secondary_card ].compact.map { |card| card.fingerprint.to_s }
      members.size == picked.size && members.sort == fingerprints.sort
    }
    return picked if twin.nil?

    picked.sort_by { |card| card.fingerprint == twin.primary_card.fingerprint ? 0 : 1 }
  end

  def picked_by_name
    words = tokens(@label).to_a
    pool = Decks::ArchetypeDetector.notable_pokemon_among(resolved_rows)
    picked = []

    MAX_SUGGESTED_CARDS.times do
      best = pool.filter_map.with_index { |card, notability|
        covered = words & tokens(card.name).to_a
        [ -covered.size, words.index(covered.first), notability, card ] if covered.any?
      }.min_by { |key| key.first(3) }
      break if best.nil?

      card = best.last
      picked << card
      words -= tokens(card.name).to_a
      pool -= [ card ]
    end

    picked
  end

  # The list resolved against the catalogue alone. Cards::ReferenceResolver never fetches — the
  # Cards::Printings rule — so a printing cartodex does not hold is simply not a fingerprint, and
  # the preview cannot turn into 45 lists' worth of card scrapes inside one web request.
  #
  # Fingerprints and not card ids: the archetype names one printing to *display* and the list holds
  # whichever the player registered, so an id-keyed resolution misses every reprint.
  def fingerprints
    resolved_rows.filter_map { |row| row[:card].fingerprint }.uniq
  end

  # Resolved once for both readers. The quantity travels because notability ranks on copies played
  # — `nonzero?`, because the resolver refuses a `0` and that line would lose its fingerprint, where
  # before it resolved at the resolver's default of one. `pokemon_subtype` is preloaded in one query
  # because notability reads `rule_box` on every card.
  def resolved_rows
    @resolved_rows ||= begin
      entries = @list_text.lines.filter_map { |line|
        match = line.strip.match(::Decks::Fetcher::CARD_LINE_RE)
        { set_code: match[3], set_number: match[4], quantity: match[1].to_i.nonzero? } if match
      }
      rows = entries.empty? ? [] : Cards::ReferenceResolver.call(entries: entries).resolved
      ActiveRecord::Associations::Preloader.new(records: rows.map { |row| row[:card] },
        associations: :pokemon_subtype).call
      rows
    end
  end
end
