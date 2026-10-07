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

    %i[show? export? tournament_pdf? cardmarket_missing? proxy_sheet_missing? stats? results? update? destroy? duplicate? share?].each do |query|
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
      %i[tournament_pdf? cardmarket_missing? proxy_sheet_missing? stats? results? update? destroy? share?].each do |query|
        refute policy.public_send(query), "expected #{viewer.inspect} to be refused #{query}"
      end
    end
  end

  # Duplicating writes nothing to the source: it makes the reader a deck of their own. So it
  # follows show?, but only for somebody signed in — a visitor has no decks to put it in.
  test "a signed-in reader may copy a shared deck, a visitor may not" do
    @deck.update!(shared: true)

    assert DeckPolicy.new(@stranger, @deck).duplicate?
    refute DeckPolicy.new(nil, @deck).duplicate?
  end

  test "nobody but the owner may copy a private deck" do
    refute DeckPolicy.new(@stranger, @deck).duplicate?
    refute DeckPolicy.new(nil, @deck).duplicate?
  end

  test "a signed-in reader may copy a tournament field list" do
    assert DeckPolicy.new(@stranger, decks(:field_list)).duplicate?
    refute DeckPolicy.new(nil, decks(:field_list)).duplicate?
  end

  test "an admin gets no special access to a private deck" do
    admin = users(:two)
    admin.update!(admin: true)

    # Deliberately no admin clause: Admin::BaseController is the admin gate, and an admin
    # opening any private deck at its normal URL is well beyond what an admin panel needs.
    refute DeckPolicy.new(admin, @deck).show?
    refute DeckPolicy.new(admin, @deck).duplicate?
  end

  test "creating a deck needs a session" do
    assert DeckPolicy.new(@owner, Deck).create?
    refute DeckPolicy.new(nil, Deck).create?
  end

  test "the shared index is open to everyone" do
    assert DeckPolicy.new(nil, Deck).shared_index?
  end
end
