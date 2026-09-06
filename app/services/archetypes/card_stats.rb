module Archetypes
  # Turns a set of tournament field lists into a deck report: for every card, how many of the
  # lists play it, in how many copies, and how settled that number is.
  #
  # The aggregation key is the card's fingerprint (see GROUPING_KEY), not its name, and the
  # production data demonstrates both halves of why in one measurement. Across the 93 recorded
  # lists of
  # Raging Bolt ex / Teal Mask Ogerpon ex there are 81 distinct card ids, 72 distinct fingerprints
  # and 70 distinct names:
  #
  #   * 81 -> 72 is the fingerprint folding nine reprints into the card they are, which a report
  #     keyed on the printing would have split into meaningless halves.
  #   * 72 -> 70 is the fingerprint *refusing* to fold: Hoothoot is three genuinely different
  #     cards there (TEF 126 at 70 HP, PRE 77 at 80 HP, SCR 114 at 70 HP with other attacks) and a
  #     player picks between them. Keyed on the name it would have read "Hoothoot 100%, 1-2
  #     copies" and hidden the choice — the same conflation Decks::ArchetypeDetector was moved off
  #     names to avoid.
  #
  # One fingerprint always means one name — for a Trainer or an Energy it hashes the name, and for
  # a Pokémon the name is part of the hash — verified on the same data: no fingerprint spans two
  # names. The report leans on that when it groups printings under a name, and it reads that name
  # off the representative printing rather than off the grouped query, so a card the key cannot
  # fold (see GROUPING_KEY) still names itself.
  class CardStats < ApplicationService
    # Display order, and the whole category vocabulary. `other` is unreachable on today's
    # catalogue — all 4720 cards categorise — and exists so that a Trainer subtype the scraper
    # learns tomorrow surfaces as a labelled bucket instead of vanishing from a report that still
    # sums to a plausible-looking 60.
    #
    # Supporter, Item, Tool, Stadium is the order Decks::ShowView already prints a decklist in —
    # it renders by iterating TRAINER_SUBTYPE_LABELS — and a member reading both pages should not
    # have to re-find the sections.
    CATEGORIES = [
      [ :pokemon,        "Pokémon" ],
      [ :supporter,      "Supporter" ],
      [ :item,           "Item" ],
      [ :tool,           "Tool" ],
      [ :stadium,        "Stadium" ],
      [ :special_energy, "Special Energy" ],
      [ :basic_energy,   "Basic Energy" ],
      [ :other,          "Other" ]
    ].freeze

    # Where a card lands in role mode when nothing says what it does. A rendered, counted section
    # and not a silent drop: on the production dump 48 of the 94 played fingerprints carry no role,
    # so dropping them would leave a report summing to half a list and still looking like one. The
    # rejected alternative reads better and is worse — falling back to the card's *type* category
    # means a reader cannot tell "this card has no role" from "nobody has curated it yet", and the
    # page starts asserting a classification it does not hold.
    NO_ROLE = :no_role
    NO_ROLE_LABEL = "No role recorded".freeze

    # `cards.subtype` is a free scraped string, not an enum. Both spellings of the tool bucket are
    # mapped because Cards::Fetcher#parse_subtype can emit either — it reads whatever follows
    # "Trainer - " on the page — while every one of the 76 tools in the catalogue today carries
    # the short one. Decks::ShowView::TRAINER_SUBTYPE_LABELS already carries the same pair.
    TRAINER_CATEGORIES = {
      "Supporter" => :supporter,
      "Item" => :item,
      "Stadium" => :stadium,
      "Tool" => :tool,
      "Pokémon Tool" => :tool
    }.freeze

    ENERGY_CATEGORIES = {
      "Basic Energy" => :basic_energy,
      "Special Energy" => :special_energy
    }.freeze

    # One printing group: the card, and how the lists that play it play it.
    #
    # `modes` is an Array because a tie is a real answer — 11 lists at 3 copies and 11 at 4 is not
    # "3", and silently picking one would state a consensus the sample does not hold.
    #
    # `labels` defaults to an empty Array rather than the bare Struct default of `nil`: this method
    # is the only caller that ever has a real answer for "which labels does this card carry", and
    # every other builder of an Entry — the styleguide's demo report, this component's own unit
    # tests — has nothing to say about labels and should not have to. Left at `nil`,
    # `NameGroupRow#type_labels`'s `flat_map(&:labels)` folds that `nil` in as a bare element
    # instead of flattening it away, and `.select(&:type?)` raises on it — which is exactly what
    # every one of those callers did until this default existed.
    Entry = Struct.new(
      :card, :fingerprint, :inclusion_count, :inclusion_pct,
      :min_copies, :max_copies, :modes, :core, :labels,
      keyword_init: true
    ) do
      def initialize(labels: [], **rest)
        super(labels: labels, **rest)
      end

      def single_quantity? = min_copies == max_copies
      # Played by every list, always in the same number: the part of the deck that is not a choice.
      def fixed? = core && single_quantity?
      def tied_mode? = modes.size > 1
    end

    # The printings of one card name, kept together. Grouping by fingerprint scatters Hoothoot's
    # three versions across a table sorted by inclusion; a reader wants to know that *some*
    # Hoothoot is in every list before they care which.
    #
    # `inclusion_count` is a distinct count of lists, never the sum of the entries' — one list may
    # play two versions.
    NameGroup = Struct.new(:name, :inclusion_count, :inclusion_pct, :entries, keyword_init: true) do
      def split? = entries.size > 1
    end

    # One section of the report. `key` is a Symbol in both modes — a CATEGORIES key in type mode,
    # a role's slug (dashes and all: `:"energy-acceleration"`) or NO_ROLE in role mode — because it
    # is only ever compared, never printed; `label` is what the reader sees.
    #
    # `cards_count` counts printings, and in role mode it **over-counts on purpose**: an entry is
    # filed under every role it carries, so Iono is under `draw` and under `disruption` and both
    # sections count it. That is why nothing prints a total across sections and why role mode says
    # so in words — see Archetypes::CardReport.
    CategoryGroup = Struct.new(:key, :label, :name_groups, keyword_init: true) do
      def cards_count = name_groups.sum { |group| group.entries.size }
    end

    # `grouping` travels on the result rather than beside it because the sections and the control
    # that chose them are rendered by one component: read off the result, the mode links cannot
    # name a grouping other than the one the sections below them were built with.
    # `proposed_roles` / `decided_roles` count the (fingerprint, role) pairs the sections below
    # were built from, split by who wrote them. The report prints roles a rule guessed beside
    # roles a human confirmed, and nothing else on the page could tell them apart — the entries
    # carry `CardLabel`s, which is what the section headings need and which says nothing about
    # provenance. Without this the page asserts "a person decides" over a sample where, on the
    # production data the day this shipped, 714 of 714 assignments were guesses.
    Result = Struct.new(
      :lists_count, :categories, :fixed_core_cards, :fixed_core_copies, :grouping,
      :proposed_roles, :decided_roles,
      keyword_init: true
    ) do
      def any? = lists_count.positive?
      def role_grouping? = grouping == :role
      def unconfirmed_roles? = proposed_roles.to_i.positive?
    end

    # Takes the standings relation rather than deck ids, so the caller cannot hand this a
    # population the report may not speak for.
    #
    # The `deck_id` filter states that intent; it does not enforce it, and no test can pretend
    # otherwise. Both queries below consume `@standings` as an `IN (SELECT deck_id …)` subquery,
    # and SQL's NULL semantics already drop the bare rows — removing this line leaves every test
    # green (checked). It stays as the declaration of what this service is allowed to see, so
    # that a future query reading `@standings` some other way inherits the restriction instead of
    # having to rediscover it.
    # `grouping` is a mode, not a second report: `Entry`, `NameGroup`, the fixed core and every
    # percentage below are computed identically either way, and only the grouping of entries into
    # sections changes. That is what makes the two views incapable of telling two stories about one
    # sample.
    #
    # Anything that is not exactly `:role` is `:type` — the clamp `ArchetypesController#index`
    # already makes for `?page=` and `#show` for `?pool=`. The value arrives from a query parameter
    # by way of the controller, so the unknown case is a reader's typo or a link-checker, and a
    # raise there would be a 500 over a spelling.
    def initialize(standings:, grouping: :type)
      @standings = standings.where.not(deck_id: nil)
      @grouping = grouping == :role ? :role : :type
    end

    def call
      return empty_result if lists_count.zero?

      Result.new(
        lists_count: lists_count,
        categories: categories,
        fixed_core_cards: fixed_entries.size,
        fixed_core_copies: fixed_entries.sum(&:min_copies),
        grouping: @grouping,
        proposed_roles: role_assignments_by_source["suggested"].to_i,
        decided_roles: role_assignments_by_source["curated"].to_i
      )
    end

    private

    # Counted off the assignments already loaded for the report — no query of its own, which is
    # what keeps /archetypes/:id at 17 — and scoped to the roles the reader is actually looking
    # at, not to the whole table.
    def role_assignments_by_source
      @role_assignments_by_source ||= role_assignments.group_by(&:source).transform_values(&:size)
    end

    def empty_result
      Result.new(lists_count: 0, categories: [], fixed_core_cards: 0, fixed_core_copies: 0,
                 grouping: @grouping)
    end

    # The key every card is aggregated under. It is the fingerprint, except for a card that has
    # none, which stands alone under its own id.
    #
    # A bare `GROUP BY cards.fingerprint` looks equivalent and is not: SQL gathers **every** NULL
    # into one group, so two unfingerprinted cards in one list merge into a single row whose
    # copies are their sum and whose name is whichever MIN() picked — a Supporter reported at
    # 6 copies, and the other card gone from the report entirely, with nothing raised. A card
    # cannot reach that state through any callback (`compute_fingerprint` is a `before_save`), so
    # this defends against `update_column`, `insert_all` and fixtures — the same state
    # Decks::ArchetypeDetector already refuses to match on and Archetypes::FingerprintSync
    # already reports rather than writes. Keeping such a card visible under its own id is the
    # point: dropping it would be the silent disappearance in a different costume.
    GROUPING_KEY = Arel.sql("COALESCE(cards.fingerprint, 'card:' || cards.id)").freeze

    # (deck, card) -> copies, in one grouped query.
    #
    # The SUM is not decoration. One list may hold two DeckCard rows for one card — two printings
    # of it, which `(deck_id, card_id)` being UNIQUE makes perfectly legal — and they are one card
    # in that list. Counted separately, the card would appear in more lists than exist, each at a
    # fraction of its real copies, and nothing would raise. Measured occurrences in the production
    # data: zero, because Limitless normalises what it publishes. The step stays for the
    # hand-typed lists, which are under no such discipline.
    def rows
      @rows ||= DeckCard
        .joins(:card)
        .where(deck_id: @standings.select(:deck_id))
        .group(Arel.sql("deck_cards.deck_id"), GROUPING_KEY)
        .pluck(
          Arel.sql("deck_cards.deck_id"),
          GROUPING_KEY,
          Arel.sql("SUM(deck_cards.quantity)")
        )
    end

    # Counted from the standings, not from the rows above, so that this is the same number
    # MetagameScope put in the sample selector and Performance put in the panel. Derived from the
    # rows it would instead be "lists holding at least one card", which is the same thing right up
    # until a list holds none — and then the page prints two listcounts and computes its
    # percentages over the one it does not show.
    def lists_count
      @lists_count ||= @standings.distinct.count(:deck_id)
    end

    # The printing each card is shown as: the one the most lists actually play, with the card id
    # breaking a tie so the choice cannot change between two loads of the same page.
    def representative_ids
      @representative_ids ||= DeckCard
        .joins(:card)
        .where(deck_id: @standings.select(:deck_id))
        .group(GROUPING_KEY, Arel.sql("deck_cards.card_id"))
        .pluck(
          GROUPING_KEY,
          Arel.sql("deck_cards.card_id"),
          Arel.sql("COUNT(DISTINCT deck_cards.deck_id)")
        )
        .group_by(&:first)
        .transform_values { |group| group.max_by { |_key, card_id, lists| [ lists, -card_id ] }[1] }
    end

    def cards
      @cards ||= Card.where(id: representative_ids.values).index_by(&:id)
    end

    def rows_by_key
      @rows_by_key ||= rows.group_by { |_deck_id, key, _copies| key }
    end

    # fingerprint -> the labels on that card, in one query for the whole report.
    #
    # Keyed on the fingerprint and not on the card id because that is what a label is about: every
    # printing of Prime Catcher is an ACE SPEC, and the report already groups on the same key. A
    # card the key cannot fold (GROUPING_KEY's 'card:<id>' fallback) matches no assignment and is
    # simply unlabelled — which is honest, and is the state a labelled row could not describe.
    #
    # `eager_load`, not `includes`: nothing else in this scope references `card_labels`, so
    # `includes` preloads it in its own second SELECT rather than joining — one query on an
    # unlabelled sample and two on a labelled one, which is exactly the number that would not
    # show up against fixtures with no assignment at all. `eager_load` forces the LEFT OUTER JOIN
    # unconditionally, so the query count no longer depends on whether any row happens to match.
    def assignments_by_fingerprint
      @assignments_by_fingerprint ||= CardLabelAssignment
        .active
        .eager_load(:card_label)
        .where(fingerprint: rows_by_key.keys)
        .group_by(&:fingerprint)
    end

    def labels_by_fingerprint
      @labels_by_fingerprint ||= assignments_by_fingerprint.transform_values do |assignments|
        assignments.map(&:card_label).sort_by { |label| [ label.position, label.slug ] }
      end
    end

    # The role half of what the report loaded, for the sentence that says how much of it a human
    # has confirmed. `entries` rather than every loaded fingerprint, because a fingerprint the
    # sample does not reach is not something the reader is being shown.
    def role_assignments
      shown = entries.map(&:fingerprint).to_set

      assignments_by_fingerprint.filter_map do |fingerprint, assignments|
        assignments.select { |assignment| assignment.card_label.role? } if shown.include?(fingerprint)
      end.flatten
    end

    # key -> the lists playing it. Kept beside the entries so a name group can count the union of
    # its printings' lists rather than re-deriving it from a name, which is how the two halves
    # came to disagree: keyed on a name the query chose and looked up by the name of the printing
    # the report chose, an unfingerprinted card could show a group at 0% sitting above its own
    # 100% sub-row.
    def lists_by_key
      @lists_by_key ||= rows_by_key.transform_values { |key_rows| key_rows.map(&:first).to_set }
    end

    def entries
      @entries ||= rows_by_key.filter_map { |key, key_rows| entry_for(key, key_rows) }
    end

    def entry_for(key, key_rows)
      card = cards[representative_ids[key]] or return nil
      copies = key_rows.map(&:last)
      inclusion = key_rows.size

      Entry.new(
        card: card,
        fingerprint: key,
        inclusion_count: inclusion,
        inclusion_pct: percentage(inclusion),
        min_copies: copies.min,
        max_copies: copies.max,
        modes: modes_of(copies),
        core: inclusion == lists_count,
        labels: labels_by_fingerprint.fetch(key, [])
      )
    end

    # Every value that ties for most frequent, ascending. See Entry#modes.
    def modes_of(copies)
      tally = copies.tally
      best = tally.values.max
      tally.select { |_copies, count| count == best }.keys.sort
    end

    def percentage(count)
      (100.0 * count / lists_count).round(1)
    end

    def fixed_entries
      @fixed_entries ||= entries.select(&:fixed?)
    end

    # Structure the database actually knows, and nothing beyond it. There is still no ACE SPEC
    # bucket here: the categories stay a partition of the list, and ACE SPEC is an annotation on
    # the name line (CardLabelAssignment), not a section — an ACE SPEC is still an Item, and moving
    # it out would break that partition. Nothing in this method could have derived the flag itself:
    # every ACE SPEC carries rarity "Ultra" and so do 93 ordinary Trainers, the string "ACE SPEC"
    # appears in `effect` on 0 of 4720 cards, and the individual card page carries it no better
    # than the search does — which is why it is imported from Limitless's card search rather than
    # guessed here.
    #
    # What a card *does* is no longer absent — it is a second grouping (`role_categories`) rather
    # than a bucket here, and it is still not derived from the text in this method. A role is a
    # property of the card, curated by hand from a rule's suggestion, so this method keeps
    # answering the one question the columns can answer on their own. Guessing a functional
    # category from a name is how a report starts stating things the data never said, which is
    # exactly why the role is a stored decision and not a match run at render time.
    def category_of(card)
      case card.card_type
      when "Pokémon" then :pokemon
      when "Trainer" then TRAINER_CATEGORIES.fetch(card.subtype.to_s, :other)
      when "Energy"  then ENERGY_CATEGORIES.fetch(card.subtype.to_s, :other)
      else :other
      end
    end

    def categories
      @grouping == :role ? role_categories : type_categories
    end

    def type_categories
      grouped = entries.group_by { |entry| category_of(entry.card) }

      CATEGORIES.filter_map do |key, label|
        category_entries = grouped[key] or next
        CategoryGroup.new(key: key, label: label, name_groups: name_groups_for(category_entries))
      end
    end

    # The same entries, regrouped — and the one place in this service where a section is not a
    # partition of the sample. An entry is filed under **every** role it carries, so a card with
    # two roles is in two sections and the sections' `cards_count` add up past the number of cards
    # played. That is the vocabulary, not an accident: Iono is draw and disruption, Prime Catcher
    # is gust and switch. The report says so in words (Archetypes::CardReport) and prints no total
    # across sections, which is the only honest way to show an overlapping classification.
    #
    # No query is added. `Entry#labels` already holds every family's label, loaded for the whole
    # report by `labels_by_fingerprint`'s single `eager_load`; only the `role?` half opens a
    # section here, and the `type?` half stays what it has always been — a badge on the name line.
    #
    # Ordered by the vocabulary's own (position, slug), never alphabetically and never by section
    # size, so two loads of one page cannot disagree; a role no entry carries is dropped exactly as
    # an empty category is. NO_ROLE is last whatever its neighbours are numbered, because it is not
    # a role.
    #
    # The Hash is keyed on the CardLabel instance: `eager_load` hands back one object per row, and
    # ActiveRecord defines `==`/`eql?`/`hash` on the id anyway, so two fingerprints carrying the
    # same role collapse to one key rather than opening two identically titled sections.
    def role_categories
      grouped = Hash.new { |hash, key| hash[key] = [] }

      entries.each do |entry|
        roles = entry.labels.select(&:role?)
        roles.any? ? roles.each { |role| grouped[role] << entry } : grouped[NO_ROLE] << entry
      end

      sections = grouped.keys.grep(CardLabel).sort_by { |role| [ role.position, role.slug ] }
        .map { |role| [ role.slug.to_sym, role.name, grouped[role] ] }
      sections << [ NO_ROLE, NO_ROLE_LABEL, grouped[NO_ROLE] ] if grouped.key?(NO_ROLE)

      sections.map do |key, label, section_entries|
        CategoryGroup.new(key: key, label: label, name_groups: name_groups_for(section_entries))
      end
    end

    # Name groups live *inside* a category rather than above it, so a name whose printings somehow
    # straddle two categories yields one group in each instead of one group filed arbitrarily.
    def name_groups_for(category_entries)
      category_entries
        .group_by { |entry| entry.card.name }
        .map { |name, name_entries| name_group_for(name, name_entries) }
        .sort_by { |group| [ -group.inclusion_count, group.name ] }
    end

    # The union of the lists playing any of this group's printings — never the sum of their
    # inclusion counts, since a list may play two of them. Measured on the production data,
    # Hoothoot's three versions total 111.9% across a name played by 73.1%.
    #
    # Taken from the entries the group actually holds, so the number above a set of sub-rows is by
    # construction a fact about those sub-rows and cannot drift from them.
    def name_group_for(name, name_entries)
      lists = name_entries.reduce(Set.new) { |all, entry| all | lists_by_key.fetch(entry.fingerprint) }.size

      NameGroup.new(
        name: name,
        inclusion_count: lists,
        inclusion_pct: percentage(lists),
        # set_number is a String holding a number most of the time and something like "SV107" the
        # rest, so it is ordered numerically first and lexically only to break the ties that
        # leaves — a plain String sort puts "114" before "77".
        entries: name_entries.sort_by do |entry|
          [ -entry.inclusion_count, entry.card.set_number.to_i, entry.card.set_number.to_s ]
        end
      )
    end
  end
end
