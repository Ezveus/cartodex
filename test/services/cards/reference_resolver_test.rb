require "test_helper"

module Cards
  class ReferenceResolverTest < ActiveSupport::TestCase
    # 1. The spec's shape in miniature: several sets, several numbers, quantities carried through.
    test "resolves a batch spanning several sets and numbers" do
      result = Cards::ReferenceResolver.call(entries: [
        { set_code: "POR", set_number: "56", quantity: 4 },
        { set_code: "POR", set_number: "57", quantity: 2 },
        { set_code: "TWM", set_number: "25", quantity: 3 },
        { set_code: "PAL", set_number: "172" },
        { "set_code" => "SVE", "set_number" => "5", "quantity" => 8 }
      ])

      assert_empty result.unresolved
      assert_equal [ cards(:honedge), cards(:doublade), cards(:teal_mask_ogerpon_ex),
                     cards(:trainer_card), cards(:basic_psychic_energy) ],
                   result.resolved.map { |entry| entry[:card] }
      assert_equal [ 4, 2, 3, 1, 8 ], result.resolved.map { |entry| entry[:quantity] }
    end

    # 2. Repeated pairs are summed and `resolved` keeps source order of first appearance. Asserted
    # as an ordered array: pass 1 hands its rows back in neither source nor numeric order, so only
    # an ordered assertion separates "in order" from "the right set of cards".
    test "sums repeated pairs and answers in source order of first appearance" do
      result = Cards::ReferenceResolver.call(entries: [
        { set_code: "POR", set_number: "56" },
        { set_code: "POR", set_number: "57" },
        { set_code: "TWM", set_number: "56" },
        { set_code: "TWM", set_number: "56" },
        { set_code: "TWM", set_number: "25" },
        { set_code: "POR", set_number: "56" }
      ])

      assert_empty result.unresolved
      assert_equal [ cards(:honedge), cards(:doublade), cards(:froakie_twm), cards(:teal_mask_ogerpon_ex) ],
                   result.resolved.map { |entry| entry[:card] }
      assert_equal [ 2, 1, 2, 1 ], result.resolved.map { |entry| entry[:quantity] }
    end

    # 3.
    test "combines a repetition with an explicit quantity" do
      result = Cards::ReferenceResolver.call(entries: [
        { set_code: "POR", set_number: "56" },
        { set_code: "POR", set_number: "56", quantity: 3 }
      ])

      assert_equal 1, result.resolved.size
      assert_equal cards(:honedge), result.resolved.first[:card]
      assert_equal 4, result.resolved.first[:quantity]
    end

    # 4. Summing is keyed on the *normalised* pair, not the raw one.
    test "sums three spellings of one printing as one reference" do
      result = Cards::ReferenceResolver.call(entries: [
        { set_code: "POR", set_number: 56 },
        { set_code: " por ", set_number: "56" },
        { set_code: "POR", set_number: " 56" }
      ])

      assert_empty result.unresolved
      assert_equal 1, result.resolved.size
      assert_equal cards(:honedge), result.resolved.first[:card]
      assert_equal 3, result.resolved.first[:quantity]
    end

    # 5. The second pass exists. `cards.set_name` is BINARY-collated and nothing upcases it on
    # write, so a lowercase row is unreachable by pass 1's indexed equality however the *input*
    # is normalised. Deleting pass 2 must turn this red.
    test "resolves a printing whose stored set code is lowercase" do
      lowercase = Card.create!(name: "Lowercase Probe", card_type: "Trainer",
                               set_name: "por", set_number: "999", rarity: "Rare")

      result = Cards::ReferenceResolver.call(entries: [ { set_code: "POR", set_number: "999" } ])

      assert_empty result.unresolved
      assert_equal [ lowercase ], result.resolved.map { |entry| entry[:card] }
    end

    # 6. Pass 1 over-fetches by the cross-product of distinct codes × distinct numbers and must
    # re-pair. Fixtures hold POR 56 and TWM 56, so a naive index on the number alone answers
    # TWM 57 with POR 57's card.
    test "re-pairs the cross-product rather than keying on the number alone" do
      result = Cards::ReferenceResolver.call(entries: [
        { set_code: "POR", set_number: "56" },
        { set_code: "TWM", set_number: "57" }
      ])

      assert_equal [ cards(:honedge) ], result.resolved.map { |entry| entry[:card] }
      assert_equal [ { set_code: "TWM", set_number: "57", reason: "no printing in the catalogue" } ],
                   result.unresolved
    end

    # 7.
    test "accepts an Integer set number identically to its String spelling" do
      integer = Cards::ReferenceResolver.call(entries: [ { set_code: "POR", set_number: 56 } ])
      string  = Cards::ReferenceResolver.call(entries: [ { set_code: "POR", set_number: "56" } ])

      assert_equal [ cards(:honedge) ], integer.resolved.map { |entry| entry[:card] }
      assert_equal integer.resolved, string.resolved
    end

    test "resolves a GG1-style collector number" do
      gallery = Card.create!(name: "Gallery Probe", card_type: "Trainer",
                             set_name: "CRZ", set_number: "GG1", rarity: "Rare")

      result = Cards::ReferenceResolver.call(entries: [ { set_code: "CRZ", set_number: "GG1" } ])

      assert_equal [ gallery ], result.resolved.map { |entry| entry[:card] }
    end

    test "squishes padding, including a non-breaking space" do
      padded = Cards::ReferenceResolver.call(entries: [
        { set_code: " POR ", set_number: " 56 " },
        { set_code: " TWM ", set_number: " 56 " }
      ])

      assert_empty padded.unresolved
      assert_equal [ cards(:honedge), cards(:froakie_twm) ], padded.resolved.map { |entry| entry[:card] }
    end

    # 8.
    test "refuses an unknown number in a known set rather than raising" do
      result = Cards::ReferenceResolver.call(entries: [ { set_code: "POR", set_number: "9999" } ])

      assert_empty result.resolved
      assert_equal [ { set_code: "POR", set_number: "9999", reason: "no printing in the catalogue" } ],
                   result.unresolved
    end

    # 9.
    test "refuses a blank set code, naming the normalised reference" do
      result = Cards::ReferenceResolver.call(entries: [ { set_code: "   ", set_number: " 56 " } ])

      assert_empty result.resolved
      assert_equal [ { set_code: "", set_number: "56", reason: "set code is missing" } ], result.unresolved
    end

    test "refuses a blank collector number, naming the normalised reference" do
      result = Cards::ReferenceResolver.call(entries: [ { set_code: " por ", set_number: nil } ])

      assert_empty result.resolved
      assert_equal [ { set_code: "POR", set_number: "", reason: "collector number is missing" } ],
                   result.unresolved
    end

    # 10. quantity refuses every non-Integer, not only 0 — an in-process call bypasses the tools'
    # JSON schema minimum entirely.
    test "refuses a quantity that is not a positive Integer" do
      # `false` is the one value that separates reading the key for nil from reading it for
      # truthiness — a truthiness read treats it as absent and silently defaults it to 1, which is
      # exactly what #read's own comment says the nil test exists to prevent. Measured: without it
      # here, mutating that line left all 16 cases green.
      [ 0, -1, "3", 2.9, true, false ].each do |quantity|
        result = Cards::ReferenceResolver.call(entries: [
          { set_code: "POR", set_number: "56", quantity: quantity }
        ])

        assert_empty result.resolved, "#{quantity.inspect} resolved"
        assert_equal [ { set_code: "POR", set_number: "56", reason: "quantity must be a positive integer" } ],
                     result.unresolved, "#{quantity.inspect} was not refused"
      end
    end

    test "defaults an absent or nil quantity to 1" do
      absent = Cards::ReferenceResolver.call(entries: [ { set_code: "POR", set_number: "56" } ])
      explicit_nil = Cards::ReferenceResolver.call(entries: [
        { set_code: "POR", set_number: "56", quantity: nil }
      ])

      assert_empty(absent.unresolved + explicit_nil.unresolved)
      assert_equal 1, absent.resolved.first[:quantity]
      assert_equal 1, explicit_nil.resolved.first[:quantity]
    end

    # 11. A reference the catalogue does not hold is a refusal, never a scrape. minitest 6 ships no
    # `stub` (minitest/mock left the gem), so the probe is a singleton method that `ensure` removes
    # again — which restores the inherited ApplicationService.call rather than a saved copy.
    test "never fetches a printing the catalogue does not hold" do
      Cards::Fetcher.define_singleton_method(:call) { |*_args, **_options| raise "Cards::Fetcher was called" }

      result = Cards::ReferenceResolver.call(entries: [ { set_code: "PBL", set_number: "999" } ])

      assert_empty result.resolved
      assert_equal [ "no printing in the catalogue" ], result.unresolved.map { |entry| entry[:reason] }
    ensure
      Cards::Fetcher.singleton_class.send(:remove_method, :call)
    end

    # 12. Flat query cost, inside `uncached`: the query cache has fooled a measurement in this
    # repository three times, and it would serve pass 1's repeat for free.
    test "costs one query whatever the batch size" do
      printings = Card.order(:id).pluck(:set_name, :set_number)
      assert_equal 13, printings.size, "fixtures moved; the batch sizes below are derived from them"

      small = to_entries(printings.first(2))
      large = to_entries(printings * 4)
      assert_equal 52, large.size

      small_cost = ActiveRecord::Base.uncached { count_queries { Cards::ReferenceResolver.call(entries: small) } }
      large_cost = ActiveRecord::Base.uncached { count_queries { Cards::ReferenceResolver.call(entries: large) } }

      assert_equal small_cost, large_cost
      assert_equal 1, large_cost
    end

    private

    def to_entries(printings)
      printings.map { |set_name, set_number| { set_code: set_name, set_number: set_number } }
    end
  end
end
