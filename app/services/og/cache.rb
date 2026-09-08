# The banner store on disk: one file per subject, named by the digest that
# describes its inputs.
#
#   Og::Cache.root.join(kind, "#{key}-#{digest}.jpg")
#
# `root` defaults to `storage/og`, which is inside the `cartodex_storage` volume
# Kamal mounts at /rails/storage, so a deploy does not throw the work away. It is
# settable because the suite runs `parallelize(workers: :number_of_processors)`:
# eight forked processes sharing one gitignored directory that also survives
# between runs would have the two named cache tests deleting each other's file
# and passing or failing by order. See test/test_helper.rb's parallelize_setup.
#
# The bound is one file *per subject* and the subject count is not bounded:
# /og/cards/:id spans the whole catalogue, 1806 cards at ~92.8 KB, in the same
# volume as the production SQLite databases. No sweep ships; a prune task is out
# of scope rather than implied.
module Og
  module Cache
    # A site payload carries `digest: nil` (there is nothing about the site to
    # digest), so its path would be "site/-.jpg" and the sibling match that keeps
    # one file per subject would have no key to anchor on. Rather than invent a
    # synthetic digest for it, the cache refuses: the site banner is rendered
    # once by a rake task into the committed public/og-default.jpg and served as
    # a static file, so nothing in the app ever asks the cache for one.
    class UncacheablePayload < StandardError; end

    mattr_accessor :root, default: Rails.root.join("storage/og"), instance_accessor: false

    # => Pathname of a readable JPEG, rendering it on a miss.
    def self.fetch(payload)
      path = path_for(payload)
      return path if path.exist?

      write(payload, path, Renderer.call(payload))
      path
    end

    def self.path_for(payload)
      if payload.kind.to_s == "site" || payload.digest.blank?
        raise UncacheablePayload,
              "#{payload.kind.inspect} payloads are not cached (digest: #{payload.digest.inspect})"
      end

      Pathname(root).join(payload.kind.to_s, "#{payload.key}-#{payload.digest}.jpg")
    end

    # Writes through a dot-prefixed temporary file and renames, so a concurrent
    # reader never opens a half-written JPEG — two crawlers hitting one cold
    # banner is the normal case, not the rare one.
    #
    # Every sibling of the same subject goes first, which is what keeps one
    # subject to one file: a renamed deck's old banner is unreachable the moment
    # its digest moves, and nothing else would ever delete it.
    def self.write(payload, path, bytes)
      directory = path.dirname
      directory.mkpath
      delete_siblings(directory, payload.key)

      temporary = directory.join(".#{path.basename}.#{Process.pid}.#{SecureRandom.hex(4)}")
      temporary.binwrite(bytes)
      File.rename(temporary, path)
      path
    end

    # The key is taken from the payload rather than parsed back out of the
    # filename, because both key shapes in play contain the separator: a deck key
    # is SecureRandom.urlsafe_base64, whose alphabet includes "-", and an
    # archetype slug is a parameterized name, which is mostly hyphens. Splitting
    # the basename on "-" would delete every archetype whose slug shares a first
    # word.
    #
    # Matched with a Regexp rather than Dir.glob for the same class of reason: a
    # glob would read any metacharacter a future key gained as a pattern. The
    # dot-prefixed temporary above cannot match, since it does not begin with the
    # key.
    def self.delete_siblings(directory, key)
      pattern = /\A#{Regexp.escape(key.to_s)}-.+\.jpg\z/

      directory.children.each do |child|
        child.delete if child.file? && child.basename.to_s.match?(pattern)
      end
    end
    private_class_method :write, :delete_siblings
  end
end
