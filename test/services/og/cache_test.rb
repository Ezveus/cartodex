require "test_helper"
require "tmpdir"

class Og::CacheTest < ActiveSupport::TestCase
  BYTES = "pretend-jpeg-bytes".b.freeze

  setup do
    # A Dir.mktmpdir per test, not per worker. The suite runs
    # parallelize(workers: :number_of_processors), and the default root —
    # storage/og — is a gitignored directory that all eight forked workers share
    # and that survives between runs, so two tests naming the same subject would
    # delete each other's file and pass or fail by order. test_helper's
    # parallelize_setup is the second line of defence; this is the first, and it
    # is the one that holds when Rails does not fork.
    @previous_root = Og::Cache.root
    @root = Pathname(Dir.mktmpdir("og-cache-test"))
    Og::Cache.root = @root

    @renders = []
    @original_renderer_call = Og::Renderer.method(:call)
    renders = @renders
    Og::Renderer.define_singleton_method(:call) { |payload|
      renders << payload.digest
      Og::Renderer::Result.new(bytes: "#{BYTES}-#{payload.digest}".b, complete: true)
    }
  end

  teardown do
    Og::Renderer.define_singleton_method(:call, @original_renderer_call)
    Og::Cache.root = @previous_root
    FileUtils.remove_entry(@root) if @root.exist?
  end

  test "renders on a miss and writes the digest-named file under the kind" do
    subject = payload(kind: "deck", key: "Zx-9_abc", digest: "0123456789abcdef")

    bytes = Og::Cache.fetch(subject)

    path = @root.join("deck", "Zx-9_abc-0123456789abcdef.jpg")
    assert_path_exists path
    assert_equal [ "0123456789abcdef" ], @renders
    assert_equal "#{BYTES}-0123456789abcdef".b, bytes
    assert_equal bytes, path.binread, "what was served and what was stored must be the same bytes"
    assert_equal 1, path.dirname.children.size,
                 "the write goes through a temporary file and renames, so nothing is left behind"
  end

  test "does not render on a hit" do
    subject = payload

    first = Og::Cache.fetch(subject)
    second = Og::Cache.fetch(subject)

    assert_equal first, second
    assert_equal 1, @renders.size, "a cached banner must be read, not redrawn"
  end

  test "a second digest for one subject deletes the first file" do
    Og::Cache.fetch(payload(digest: "1111111111111111"))
    Og::Cache.fetch(payload(digest: "2222222222222222"))

    directory = @root.join("deck")
    assert_path_exists directory.join("abc123-2222222222222222.jpg")
    refute directory.join("abc123-1111111111111111.jpg").exist?,
           "one subject holds one file, or the cache grows without bound"
    assert_equal 1, directory.children.size
  end

  # The discriminating case, and the first version of this test did not have it. It compared
  # "raging-bolt-ex" with "raging-bolt-ogerpon", where neither is a prefix of the other — so it
  # only caught the split-the-basename-on-"-" mistake the code never made, and passed happily
  # against the shipped `/\A#{key}-.+\.jpg\z/`, under which a short key matches a longer key's file.
  #
  # A strict prefix is the real shape, and archetypes produce it as a matter of course:
  # `auto_generate_name` builds a pair as "Primary / Secondary", so the single-member archetype's
  # slug is the pair's slug truncated at a hyphen. On the production dump 19 of 79 archetypes were
  # in such a pair, and one write to `mega-greninja-ex` evicted five other archetypes' banners.
  test "a subject whose key is a strict prefix of another's keeps both files" do
    parent = "raging-bolt-ex"
    child = "raging-bolt-ex-teal-mask-ogerpon-ex"

    Og::Cache.fetch(payload(kind: "archetype", key: child, digest: "1111111111111111"))
    Og::Cache.fetch(payload(kind: "archetype", key: parent, digest: "2222222222222222"))

    directory = @root.join("archetype")
    assert_path_exists directory.join("#{child}-1111111111111111.jpg"),
                       "a shorter key must not match a longer key's file"
    assert_path_exists directory.join("#{parent}-2222222222222222.jpg")
  end

  # A digest is DIGEST_LENGTH hex characters, so a *key* that happens to look like "key-<hex>"
  # cannot be mistaken for a sibling of "key" either. The inverse of the test above, and the reason
  # the pattern anchors on the digest's shape rather than on anything about the key.
  test "a key that ends in something digest-shaped is still its own subject" do
    Og::Cache.fetch(payload(kind: "archetype", key: "alpha-0123456789abcdef", digest: "1111111111111111"))
    Og::Cache.fetch(payload(kind: "archetype", key: "alpha", digest: "2222222222222222"))

    directory = @root.join("archetype")
    assert_path_exists directory.join("alpha-0123456789abcdef-1111111111111111.jpg")
    assert_path_exists directory.join("alpha-2222222222222222.jpg")
  end

  # A failed art is invisible to the digest — that is computed from the record and the art *URLs*,
  # never from whether the fetch worked — so a degraded banner stored at that address would stay
  # there until the subject was next edited, with `immutable` telling every client not to ask
  # again. One CDN blip at the moment a link is first unfurled would cost that deck its artwork
  # for good. So the bytes are served and nothing is written.
  test "a degraded render is served but never stored" do
    Og::Renderer.define_singleton_method(:call) { |_payload|
      Og::Renderer::Result.new(bytes: "degraded".b, complete: false)
    }

    bytes = Og::Cache.fetch(payload)

    assert_equal "degraded".b, bytes
    refute @root.join("deck").exist?, "an incomplete banner must not be cached"

    Og::Renderer.define_singleton_method(:call) { |_payload|
      Og::Renderer::Result.new(bytes: "whole".b, complete: true)
    }
    assert_equal "whole".b, Og::Cache.fetch(payload), "the next request must try again"
    assert_path_exists @root.join("deck", "abc123-deadbeefdeadbeef.jpg")
  end

  test "refuses a site payload rather than keying it on a nil digest" do
    error = assert_raises Og::Cache::UncacheablePayload do
      Og::Cache.fetch(payload(kind: "site", key: nil, digest: nil))
    end

    assert_match(/site/, error.message)
    assert_empty @renders, "the site banner is a committed file, not a cache entry"
    assert_empty @root.children
  end

  test "refuses a subject payload with no digest" do
    assert_raises Og::Cache::UncacheablePayload do
      Og::Cache.fetch(payload(digest: nil))
    end

    # Without this the path is "deck/abc123-.jpg" and nothing about that name is a digest, so the
    # sibling pattern would never match it again — silently, since
    # Struct.new(keyword_init: true) stores nil for a keyword nobody passed.
    assert_empty @renders
  end

  test "root is what decides where a banner lands" do
    elsewhere = Pathname(Dir.mktmpdir("og-cache-elsewhere"))
    Og::Cache.root = elsewhere

    Og::Cache.fetch(payload)

    assert_path_exists elsewhere.join("deck", "abc123-deadbeefdeadbeef.jpg")
  ensure
    FileUtils.remove_entry(elsewhere) if elsewhere&.exist?
  end

  private

  def payload(kind: "deck", key: "abc123", title: "Raging Bolt ex", subtitle: nil,
              art_urls: [], digest: "deadbeefdeadbeef")
    Og::Payload.new(kind: kind, key: key, title: title, subtitle: subtitle,
                    art_urls: art_urls, digest: digest)
  end
end
