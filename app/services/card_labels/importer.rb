# Write one label's assignments from what Limitless's card search lists.
#
# Three rules, and each is a refusal to do the obvious thing:
#
#   * it writes on the *fingerprint*, so a printing of an already-labelled card that arrives later
#     inherits the label with nothing re-run;
#   * it never modifies a row it did not create, so a curated decision — including a refusal —
#     outranks the source;
#   * it never deletes. An assignment the source no longer lists is reported, because a page
#     truncated by a transport failure is indistinguishable from a card the source dropped, and
#     only one of those two should depopulate a label.
#
# It never creates a Card either: a printing the catalogue does not hold is counted. Acquiring
# cards is CardSets::Importer's job, and since #121 a known printing is never re-scraped.
class CardLabels::Importer < ApplicationService
  Result = Struct.new(
    :created, :already_present, :missing_printings, :unfingerprinted,
    :unlisted_fingerprints, :announced_count, :read_count,
    keyword_init: true
  ) do
    def complete? = announced_count.nil? || announced_count == read_count
  end

  # `search:` is injected so a test can drive this without HTTP, and so stage 2 can point a role
  # importer at a different reader if one ever exists.
  def initialize(card_label, search: CardLabels::LimitlessSearch)
    @label = card_label
    @search = search
  end

  def call
    found = @search.call(@label.source_query)
    resolved = resolve(found.printings)

    serialized_transaction { write(resolved[:cards]) }

    Result.new(
      created: @created,
      already_present: @already_present,
      missing_printings: resolved[:missing],
      unfingerprinted: resolved[:unfingerprinted],
      unlisted_fingerprints: unlisted(resolved[:cards]),
      announced_count: found.announced_count,
      read_count: found.printings.size
    )
  end

  private

  # One query for the whole label rather than one per printing: is:ex is 986 of them. Built in Arel
  # rather than a "(set_name = ? AND set_number = ?) OR ..." string — that chain is a left-deep
  # expression tree and blows SQLite's compile-time SQLITE_MAX_EXPR_DEPTH. Measured against this
  # exact query shape on sqlite3 3.53.2 (gem sqlite3 2.9.6): 995 terms parse, 1000 raise
  # "Expression tree is too large (maximum depth 1000)", and is:ex's 986 printings sit close enough
  # that one new set of ex cards would cross it from an unrescued admin action. A row-value IN list
  # is one expression holding an ExprList rather than a chain of ORs, so its terms cost no depth
  # regardless of count — checked at 986, 1200 and 5000. It has to be built in Arel and not as an
  # interpolated "(set_name, set_number) IN (#{...})" string: Brakeman correctly flags that shape as
  # SQL injection (it folds a joined fragment back into the interpolation too, so de-interpolating
  # does not satisfy it), because nothing in a plain string shows it the values are bound rather
  # than spliced in. Building the identical predicate in Arel keeps it visibly parameterised, so
  # the check can actually read this method rather than needing a suppression — do not "simplify"
  # this back into a string.
  def resolve(printings)
    # Not a crash guard against the IN below — "(set_name, set_number) IN ()" is valid SQLite and
    # simply matches nothing — just a wasted query worth skipping outright.
    return { cards: [], missing: [], unfingerprinted: [] } if printings.empty?

    pairs = printings.map { |printing| [ printing.set_code, printing.number ] }
    table = Card.arel_table
    key = Arel::Nodes::Grouping.new([ table[:set_name], table[:set_number] ])
    tuples = pairs.map { |code, number|
      Arel::Nodes::Grouping.new([ Arel::Nodes.build_quoted(code), Arel::Nodes.build_quoted(number) ])
    }
    cards = Card.where(Arel::Nodes::In.new(key, tuples))
                .index_by { |card| [ card.set_name, card.set_number ] }

    missing = pairs.reject { |pair| cards.key?(pair) }.map { |set_code, number| "#{set_code} #{number}" }
    held = pairs.filter_map { |pair| cards[pair] }
    unfingerprinted = held.select { |card| card.fingerprint.blank? }

    {
      cards: held - unfingerprinted,
      missing: missing,
      unfingerprinted: unfingerprinted.map { |card| "#{card.set_name} #{card.set_number}" }
    }
  end

  # find_or_initialize_by + a persisted? guard, not find_or_create_by! and not upsert: leaving an
  # existing row exactly as it is *is* the rule, and either of those would quietly rewrite a
  # curated decision back to "imported".
  def write(cards)
    @created = 0
    @already_present = 0

    cards.group_by(&:fingerprint).each do |fingerprint, printings|
      assignment = CardLabelAssignment.find_or_initialize_by(card_label: @label, fingerprint: fingerprint)

      if assignment.persisted?
        @already_present += 1
        next
      end

      assignment.update!(card: printings.first, source: "imported")
      @created += 1
    end
  end

  # Only rows this importer wrote: a curated assignment the source never listed is not a stray, it
  # is somebody's decision. An empty `cards` is not special-cased into reporting nothing: if the
  # source affirmatively lists no printings at all, every currently-imported row on the label
  # genuinely is unlisted, and reporting all of them — never deleting — is the same rule applied at
  # its edge rather than a different one. (`where.not(fingerprint: [])` is `1=1`, so this really
  # does return every imported fingerprint on the label in that case.) Unreachable through the real
  # LimitlessSearch today, which raises ParseError on an empty grid before this is ever called, but
  # `search:` exists precisely so another reader can be injected without that guard.
  def unlisted(cards)
    @label.assignments.imported.where.not(fingerprint: cards.map(&:fingerprint)).pluck(:fingerprint)
  end
end
