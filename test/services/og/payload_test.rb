require "test_helper"

class Og::PayloadTest < ActiveSupport::TestCase
  # The reason validate! exists at all. Struct.new(keyword_init: true) raises ArgumentError on an
  # *extra* keyword but stores nil for a *missing* one — measured, and written down at
  # app/views/components/styleguide/page_view.rb:394 for the same reason. A builder that forgot
  # `digest:` would otherwise hand the cache a path of `…/key-.jpg` and the page an empty `?v=`,
  # with nothing raising anywhere.
  test "a missing keyword is stored as nil rather than refused by the Struct" do
    payload = Og::Payload.new(kind: "deck", key: "abc", title: "My deck")

    assert_nil payload.digest
    assert_nil payload.art_urls
  end

  test "a subject payload with no digest is refused" do
    payload = Og::Payload.new(kind: "deck", key: "abc", title: "My deck", subtitle: nil, art_urls: [])

    error = assert_raises(ArgumentError) { payload.validate! }
    assert_match(/digest/, error.message)
  end

  # The one kind that legitimately has none: the site banner is a committed file, so there is
  # nothing for a cache-buster to bust.
  test "the site payload is the one kind that needs no digest" do
    payload = Og::Payload.new(kind: "site", key: nil, title: "Cartodex", subtitle: "x",
                              art_urls: [], digest: nil)

    assert_nothing_raised { payload.validate! }
  end

  test "a payload with no kind is refused" do
    payload = Og::Payload.new(kind: nil, key: "abc", title: "My deck", subtitle: nil,
                              art_urls: [], digest: "0123456789abcdef")

    error = assert_raises(ArgumentError) { payload.validate! }
    assert_match(/kind/, error.message)
  end

  test "a payload with a blank title is refused" do
    payload = Og::Payload.new(kind: "deck", key: "abc", title: "  ", subtitle: nil,
                              art_urls: [], digest: "0123456789abcdef")

    error = assert_raises(ArgumentError) { payload.validate! }
    assert_match(/title/, error.message)
  end

  # The digest is the subject's address on disk and in the `?v=` of every page that links it, so
  # the formula is pinned rather than described: changing it orphans every cached file and every
  # preview a chat client has already stored.
  test "the digest is 16 hex characters of SHA-256 over the unit-separated parts" do
    digest = Og::Payload.digest_of([ 1, "deck", "abc" ])

    assert_match(/\A[0-9a-f]{16}\z/, digest)
    assert_equal Digest::SHA256.hexdigest([ 1, "deck", "abc" ].join("\x1f")).first(16), digest
  end

  test "two different part lists cannot join to the same digest" do
    assert_not_equal Og::Payload.digest_of([ "a", "b" ]), Og::Payload.digest_of([ "ab" ])
  end

  # A deck holding no cards has no newest deck-card timestamp, so nil is a real part value. It
  # joins as an empty field: deterministic, which is all this needs to be.
  test "a nil part is stringified consistently" do
    assert_equal Og::Payload.digest_of([ "a", "" ]), Og::Payload.digest_of([ "a", nil ])
  end
end
