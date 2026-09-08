require "test_helper"

class Og::SitePayloadTest < ActiveSupport::TestCase
  # Every member is asserted, here and in the other three builder tests, because a payload is a
  # Struct built by keyword: a member the builder forgets is stored as nil rather than refused
  # (see Og::PayloadTest), so a test that only looks at the member it is about would not see it.
  test "the site payload names the app and carries no subject" do
    payload = Og::SitePayload.call

    assert_equal "site", payload.kind
    assert_nil payload.key
    assert_equal "Cartodex", payload.title
    assert_equal "Pokémon TCG collection, decks and tournament results", payload.subtitle
    assert_equal [], payload.art_urls
    assert_nil payload.digest
  end

  # The kind reaches Phlex as an attribute *value* (`content:`), and Phlex dasherizes a Symbol
  # value. "site" and :site would render the same here, which is exactly why this is asserted
  # rather than assumed.
  test "the kind is a String, never a Symbol" do
    assert_kind_of String, Og::SitePayload.call.kind
  end
end
