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
      "#{BYTES}-#{payload.digest}".b
    }
  end

  teardown do
    Og::Renderer.define_singleton_method(:call, @original_renderer_call)
    Og::Cache.root = @previous_root
    FileUtils.remove_entry(@root) if @root.exist?
  end

  test "renders on a miss and writes the digest-named file under the kind" do
    subject = payload(kind: "deck", key: "Zx-9_abc", digest: "0123456789abcdef")

    path = Og::Cache.fetch(subject)

    assert_equal @root.join("deck", "Zx-9_abc-0123456789abcdef.jpg"), path
    assert path.exist?
    assert_equal [ "0123456789abcdef" ], @renders
    assert_equal "#{BYTES}-0123456789abcdef".b, path.binread
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
    old = Og::Cache.fetch(payload(digest: "1111111111111111"))
    new = Og::Cache.fetch(payload(digest: "2222222222222222"))

    assert new.exist?
    refute old.exist?, "one subject holds one file, or the cache grows without bound"
    assert_equal [ new ], new.dirname.children.sort
  end

  test "a subject whose key shares a prefix with another keeps its own file" do
    # The discriminating case for how siblings are matched. An archetype slug is
    # a parameterized name, so hyphens are the norm rather than the exception:
    # deriving the subject by splitting the filename on "-" makes "raging-bolt"
    # of both of these and the second write deletes the first archetype's banner.
    one = Og::Cache.fetch(payload(kind: "archetype", key: "raging-bolt-ex", digest: "1111111111111111"))
    two = Og::Cache.fetch(payload(kind: "archetype", key: "raging-bolt-ogerpon", digest: "2222222222222222"))

    assert one.exist?, "another archetype's banner is not this one's sibling"
    assert two.exist?
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

    # Without this the path is "deck/abc123-.jpg", the sibling match is
    # "abc123-.+", and every later digest for that deck deletes the file it just
    # wrote — silently, since Struct.new(keyword_init: true) stores nil for a
    # keyword nobody passed.
    assert_empty @renders
  end

  test "root is what decides where a banner lands" do
    elsewhere = Pathname(Dir.mktmpdir("og-cache-elsewhere"))
    Og::Cache.root = elsewhere

    path = Og::Cache.fetch(payload)

    assert path.to_s.start_with?(elsewhere.to_s)
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
