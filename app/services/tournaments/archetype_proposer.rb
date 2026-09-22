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
  Proposal = Struct.new(:archetype, :verdict, :candidates, keyword_init: true) do
    def decided? = verdict == :decided
  end

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
    return Proposal.new(archetype: nil, verdict: :no_candidate, candidates: []) if scored.empty?

    ranked = rank(scored)

    Proposal.new(archetype: archetype_for(ranked), verdict: verdict_for(ranked),
      candidates: ranked.map { |candidate| candidate[:archetype] })
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

  # The list resolved against the catalogue alone. Cards::ReferenceResolver never fetches — the
  # Cards::Printings rule — so a printing cartodex does not hold is simply not a fingerprint, and
  # the preview cannot turn into 45 lists' worth of card scrapes inside one web request.
  #
  # Fingerprints and not card ids: the archetype names one printing to *display* and the list holds
  # whichever the player registered, so an id-keyed resolution misses every reprint.
  def fingerprints
    entries = @list_text.lines.filter_map { |line|
      match = line.strip.match(::Decks::Fetcher::CARD_LINE_RE)
      { set_code: match[3], set_number: match[4] } if match
    }
    return [] if entries.empty?

    Cards::ReferenceResolver.call(entries: entries)
      .resolved.filter_map { |row| row[:card].fingerprint }.uniq
  end
end
