require "test_helper"

class DeckPolicyTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @stranger = users(:two)
    @deck = decks(:one)
    @deck.update!(user: @owner, shared: false)
  end

  test "an owner may do everything to their own deck" do
    policy = DeckPolicy.new(@owner, @deck)

    %i[show? export? tournament_pdf? stats? results? update? destroy? duplicate? share?].each do |query|
      assert policy.public_send(query), "expected the owner to be allowed #{query}"
    end
  end

  test "nobody but the owner may see a private deck" do
    refute DeckPolicy.new(@stranger, @deck).show?
    refute DeckPolicy.new(nil, @deck).show?
  end

  test "anybody may see and export a shared deck" do
    @deck.update!(shared: true)

    [ @stranger, nil ].each do |viewer|
      policy = DeckPolicy.new(viewer, @deck)
      assert policy.show?, "expected #{viewer.inspect} to be allowed show?"
      assert policy.export?, "expected #{viewer.inspect} to be allowed export?"
    end
  end

  test "sharing a deck exposes neither its record nor its writes" do
    @deck.update!(shared: true)

    [ @stranger, nil ].each do |viewer|
      policy = DeckPolicy.new(viewer, @deck)
      %i[tournament_pdf? stats? results? update? destroy? duplicate? share?].each do |query|
        refute policy.public_send(query), "expected #{viewer.inspect} to be refused #{query}"
      end
    end
  end

  test "an admin gets no special access to a private deck" do
    admin = users(:two)
    admin.update!(admin: true)

    # Deliberately no admin clause: Admin::BaseController is the admin gate, and an admin
    # opening any private deck at its normal URL is well beyond what an admin panel needs.
    refute DeckPolicy.new(admin, @deck).show?
  end

  test "creating a deck needs a session" do
    assert DeckPolicy.new(@owner, Deck).create?
    refute DeckPolicy.new(nil, Deck).create?
  end

  test "the shared index is open to everyone" do
    assert DeckPolicy.new(nil, Deck).shared_index?
  end

  test "the scope is mine plus everybody's shared, or just the shared ones" do
    mine_private = @deck
    theirs_shared = decks(:two)
    theirs_shared.update!(user: @stranger, shared: true)

    signed_in = DeckPolicy::Scope.new(@owner, Deck).resolve
    assert_includes signed_in, mine_private
    assert_includes signed_in, theirs_shared

    visitor = DeckPolicy::Scope.new(nil, Deck).resolve
    refute_includes visitor, mine_private
    assert_includes visitor, theirs_shared
  end
end
