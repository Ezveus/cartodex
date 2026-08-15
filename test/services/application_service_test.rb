require "test_helper"

class ApplicationServiceTest < ActiveSupport::TestCase
  # serialized_transaction has two branches and the rest of the suite only ever
  # exercises one: transactional fixtures keep a transaction open for every
  # test, so every service call takes the savepoint branch. The branch that
  # actually opens a transaction — the only one production ever takes — needs
  # the fixtures' transaction out of the way to run at all.
  self.use_transactional_tests = false

  class Probe < ApplicationService
    def call
      serialized_transaction { Deck.first && :ran }
    end
  end

  class FailingProbe < ApplicationService
    attr_reader :deck_id

    def initialize(user:)
      @user = user
    end

    def call
      serialized_transaction do
        @deck_id = @user.decks.create!(name: "Nested work").id
        raise "nested failure"
      end
    end
  end

  test "runs the block when no transaction is open" do
    assert_equal :ran, Probe.call
  end

  test "takes SQLite's write lock before the block reads anything" do
    statements = capture_statements { Probe.call }
    began_at = statements.index { |sql| sql.match?(/\ABEGIN/i) }
    read_at = statements.index { |sql| sql.match?(/FROM "decks"/) }

    assert began_at, "expected a BEGIN, got: #{statements.inspect}"
    assert read_at, "expected the block's read, got: #{statements.inspect}"
    assert_match(/\ABEGIN IMMEDIATE TRANSACTION/i, statements[began_at])
    assert_operator began_at, :<, read_at
  end

  # Unwinds its own work without taking the caller's with it — the point of the
  # nested `requires_new` savepoint, asserted through what it does rather than
  # through the SAVEPOINT statement, which Rails emits lazily.
  test "unwinds only its own work inside a caller's transaction" do
    probe = FailingProbe.new(user: users(:one))
    caller_deck = nil

    ActiveRecord::Base.transaction do
      caller_deck = users(:one).decks.create!(name: "Caller's own work")
      assert_raises(RuntimeError) { probe.call }

      # Both asserted before the caller's own rollback, which would otherwise
      # undo the nested work too and make the first assertion vacuous.
      assert_not Deck.where(id: probe.deck_id).exists?, "the nested block's work outlived its own failure"
      assert Deck.where(id: caller_deck.id).exists?, "the nested rollback took the caller's work with it"

      raise ActiveRecord::Rollback
    end

    assert_not Deck.where(id: caller_deck.id).exists?, "the caller's rollback left work behind"
  end

  private

  def capture_statements(&block)
    [].tap do |statements|
      ActiveSupport::Notifications.subscribed(
        ->(*, payload) { statements << payload[:sql] },
        "sql.active_record",
        &block
      )
    end
  end
end
