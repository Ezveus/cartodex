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
#
# And that ceiling is really a floor, in two ways worth being explicit about rather than leaving
# to be discovered. The key is the subject's *address*, so an archetype rename moves its slug and
# strands the old file — nothing is that file's sibling ever again. A deleted deck, archetype or
# card strands its file the same way. Second, the endpoint is unauthenticated: at 60 requests a
# minute an anonymous client can walk the card catalogue and fill ~170 MB in about half an hour,
# which is a disk-usage question and not a correctness one, but it is not a thing only a member
# could do.
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

    # => String, JPEG bytes: read from disk on a hit, rendered on a miss.
    #
    # Bytes and not a Pathname, deliberately. The controller used to send_file the path this
    # returned, which made the endpoint depend on that file still existing a moment later — and a
    # concurrent write of the same subject could remove it between the check and the send, which
    # raised ActionController::MissingFile: not in Rails' rescue_responses, so a 500. Handing back
    # the bytes removes the window rather than narrowing it, and 92 KB through send_data costs
    # nothing worth measuring.
    #
    # **A degraded render is served and not stored.** If any art failed to resolve, the banner is
    # correct-looking but incomplete, and its digest does not know that — the digest is computed
    # from the record and the art *URLs*, never from whether the fetch worked. Caching it would
    # pin the incomplete banner at that address for as long as the subject is unedited, with
    # `immutable` telling every client never to ask again: one CDN blip at the moment a link is
    # first unfurled would silently cost that deck its artwork forever. So the miss path returns
    # the bytes and writes nothing, and the next request tries the CDN again.
    def self.fetch(payload)
      path = path_for(payload)
      cached = read(path)
      return cached if cached

      result = Renderer.call(payload)
      write(payload, path, result.bytes) if result.complete
      result.bytes
    end

    # Errno::ENOENT is rescued rather than prevented, because `exist?` followed by `binread` is
    # check-then-act however carefully the writer is ordered: a concurrent write of another digest
    # for the same subject prunes this file, and two crawlers on one subject is the normal case.
    # Left to propagate it is a 500 on a public endpoint for a file we could simply redraw.
    def self.read(path)
      path.binread if path.exist?
    rescue Errno::ENOENT
      nil
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
    # Every other digest of the *same* subject then goes, which is what keeps one subject to one
    # file: a deck whose decklist changed is unreachable at its old digest, and nothing else would
    # ever delete it. A subject whose *key* changed is a different matter — see the note above.
    def self.write(payload, path, bytes)
      directory = path.dirname
      directory.mkpath

      # Rename first, prune second, and the order matters. Pruning first opened a window in which
      # a concurrent reader that had already passed Cache.fetch's `path.exist?` found its file
      # deleted a moment later, and send_file then raised ActionController::MissingFile — which is
      # not in Rails' rescue_responses, so a 500 rather than a 404. Reproduced by a review. This
      # way the new file is in place before anything is removed, and the reader either sees the old
      # path or the new one, both of which exist.
      temporary = directory.join(".#{path.basename}.#{Process.pid}.#{SecureRandom.hex(4)}")
      temporary.binwrite(bytes)
      File.rename(temporary, path)
      delete_siblings(directory, payload.key, except: path)
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
    #
    # The digest is anchored as exactly DIGEST_LENGTH hex characters, and that is the whole
    # correctness of this method. Written as `.+` — and it was — a key that is a strict *prefix* of
    # another key matches that other subject's file, so one write evicted a different subject's
    # banner. Archetype slugs make that the normal case rather than a corner: `auto_generate_name`
    # builds a pair as "Primary / Secondary", so the single-member archetype's slug is a prefix of
    # the pair's followed by "-". Measured on the production dump, 19 of 79 archetypes were in such
    # a pair and one write to `mega-greninja-ex` evicted five other archetypes at once. Deck keys
    # (fixed-length base64) and card ids (digits) could never collide, which is why the bug hid.
    def self.delete_siblings(directory, key, except: nil)
      pattern = /\A#{Regexp.escape(key.to_s)}-\h{#{DIGEST_LENGTH}}\.jpg\z/

      directory.children.each do |child|
        next if except && child == except

        child.delete if child.file? && child.basename.to_s.match?(pattern)
      end
    end
    private_class_method :read, :write, :delete_siblings
  end
end
