module Cards
  # Turns a batch of `(set code, collector number, quantity)` references into the printings the
  # catalogue already holds, plus a refusal per reference it cannot answer.
  #
  # **It never fetches.** Cards::Fetcher goes to the network at roughly 0.7 s per unknown printing,
  # which is exactly what the callers of this service — bulk writes — must not do while they hold
  # SQLite's single write lock. A reference the catalogue does not hold is a refusal the caller
  # reports, not a scrape.
  #
  # Resolution is two passes, and the second one is not a fallback for tidiness. Pass 1 is a single
  # indexed read over the distinct codes and the distinct numbers, which over-fetches by their
  # cross-product (measured: 357 rows for 52 real references) and is therefore re-paired in Ruby on
  # the *pair*, never on the number alone — fixtures alone already hold POR 56 and TWM 56. Pass 2
  # re-asks whatever pass 1 left, through Card.in_set_code, which is the case-insensitive scanning
  # form: `cards.set_name` is BINARY-collated and nothing enforces its casing (Cards::Fetcher takes
  # it from a URL path segment), so a lowercase row is unreachable by pass 1 however the input is
  # normalised. Measured at 52 references, the indexed form costs 0.000068 s against 0.025 s for the
  # scanning one — hence fast first, correct second, rather than the scan for everything.
  class ReferenceResolver < ApplicationService
    Entry = Struct.new(:set_code, :set_number, :quantity, keyword_init: true)
    Result = Struct.new(:resolved, :unresolved, keyword_init: true)

    MISSING_SET_CODE = "set code is missing".freeze
    MISSING_SET_NUMBER = "collector number is missing".freeze
    INVALID_QUANTITY = "quantity must be a positive integer".freeze
    NOT_IN_CATALOGUE = "no printing in the catalogue".freeze

    def initialize(entries:)
      @entries = entries
      # Insertion-ordered, which is what makes `resolved` come back in source order of first
      # appearance: pass 1 hands its rows back in neither source nor numeric order.
      @pending = {}
      @unresolved = []
    end

    def call
      Array(@entries).each { |raw| accept(normalize(raw)) }

      Result.new(resolved: resolve_pending, unresolved: @unresolved)
    end

    private

    # `squish`, never `strip`: a reference copy-pasted out of a web page carries U+00A0, which
    # String#strip leaves in place and String#squish folds.
    def normalize(raw)
      Entry.new(
        set_code: read(raw, :set_code).to_s.squish.upcase,
        set_number: read(raw, :set_number).to_s.squish,
        quantity: read(raw, :quantity)
      )
    end

    # Entries arrive from an MCP payload as well as from Ruby, so a key may be either shape.
    # Tested for nil rather than truthiness, so that a `false` quantity is refused rather than
    # silently defaulted.
    def read(raw, key)
      value = raw[key]
      value.nil? ? raw[key.to_s] : value
    end

    def accept(entry)
      if entry.set_code.blank?
        refuse(entry, MISSING_SET_CODE)
      elsif entry.set_number.blank?
        refuse(entry, MISSING_SET_NUMBER)
      elsif !valid_quantity?(entry.quantity)
        refuse(entry, INVALID_QUANTITY)
      else
        pair = [ entry.set_code, entry.set_number ]
        @pending[pair] = @pending.fetch(pair, 0) + (entry.quantity || 1)
      end
    end

    # The tools' JSON schema already carries `minimum: 1`, but an in-process call bypasses it
    # entirely — the same reason McpTool#positive_quantity? exists. `true.is_a?(Integer)` is false,
    # so a boolean is refused here rather than summed as one copy.
    def valid_quantity?(quantity)
      quantity.nil? || (quantity.is_a?(Integer) && quantity.positive?)
    end

    def refuse(entry, reason)
      @unresolved << { set_code: entry.set_code, set_number: entry.set_number, reason: reason }
    end

    def resolve_pending
      return [] if @pending.empty?

      index = indexed_pass

      @pending.filter_map do |(set_code, set_number), quantity|
        card = index[[ set_code, set_number ]] || scanning_pass(set_code, set_number)

        if card
          { card: card, quantity: quantity }
        else
          @unresolved << { set_code: set_code, set_number: set_number, reason: NOT_IN_CATALOGUE }
          nil
        end
      end
    end

    # One statement whatever the batch size. Keyed on the pair, because the cross-product it
    # fetches holds rows no reference asked for.
    def indexed_pass
      pairs = @pending.keys

      Card.where(set_name: pairs.map(&:first).uniq)
          .where(set_number: pairs.map(&:last).uniq)
          .index_by { |card| [ card.set_name.upcase, card.set_number ] }
    end

    def scanning_pass(set_code, set_number)
      Card.in_set_code(set_code).find_by(set_number: set_number)
    end
  end
end
