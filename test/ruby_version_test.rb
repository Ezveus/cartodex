require "test_helper"

# The Ruby version is declared six times over, and until this test existed nothing made the six
# agree. They had already drifted: `.ruby-version` said 3.4.1 while `mise.toml` said 4.0.1, so
# every local `bin/rubocop` analysed as Ruby 3.4 on a 4.0.1 interpreter and a lint result could
# not be compared with CI's. Nothing about that was visible — no command failed, no file
# complained, and the two spellings of the same fact simply answered different questions.
#
# `.ruby-version` is the reference, and the reason is itself one of the declarations: all six
# jobs in `.github/workflows/ci.yml` say `ruby-version: .ruby-version`, so whatever that file
# holds is the version the five gates and the deploy actually run under. Which is why the
# workflow is checked too — pin one job to a literal and every other assertion here would go on
# passing while the gates ran on something else, the exact silent failure this test exists to
# stop.
#
# This is the only test at the root of `test/` rather than in a directory mirroring a code
# location, and that is deliberate: every other directory under `test/` answers to something in
# `app/` or `lib/`, and this one answers to the repository's own configuration files. There is
# nowhere for it to mirror.
class RubyVersionTest < ActiveSupport::TestCase
  REFERENCE = File.read(Rails.root.join(".ruby-version")).strip.delete_prefix("ruby-").freeze

  # A bare `4.0.6` and not `ruby-4.0.6` in `.ruby-version` would still install correctly —
  # setup-ruby and mise both accept either — but the Dockerfiles interpolate their `ARG` into an
  # image tag (`ruby:$RUBY_VERSION-slim`), where the prefix is not a spelling variant: it names
  # no image. Pinning the shape here is what lets the comparisons below be string equality.
  test "the reference is a ruby-prefixed three-part version" do
    assert_match(/\Aruby-\d+\.\d+\.\d+\n?\z/, File.read(Rails.root.join(".ruby-version")))
  end

  # What makes `.ruby-version` the reference at all. Checked as a set rather than a count, so a
  # job added or removed does not need editing here, but a job pinned to a literal version — or
  # to a matrix — fails.
  test "every CI job installs Ruby from .ruby-version" do
    declared = scan(".github/workflows/ci.yml", /^\s*ruby-version:\s*(\S+)/)

    assert_not_empty declared, "no job in ci.yml declares a ruby-version"
    assert_equal [ ".ruby-version" ], declared.uniq
  end

  # mise.toml is what actually provisions the interpreter on a developer's machine, and it wins
  # over `.ruby-version` when the two disagree. It is therefore the one copy whose drift is
  # completely silent: the wrong Ruby just runs.
  test "mise.toml provisions the reference version" do
    assert_equal REFERENCE, declared_in("mise.toml", /^ruby\s*=\s*"([^"]+)"/)
  end

  # The production image's tag. Wrong here and the deploy runs a Ruby the five gates never saw.
  test "the production Dockerfile builds on the reference version" do
    assert_equal REFERENCE, declared_in("Dockerfile", /^ARG RUBY_VERSION=(.+)$/)
  end

  test "the devcontainer builds on the reference version" do
    assert_equal REFERENCE, declared_in(".devcontainer/Dockerfile", /^ARG RUBY_VERSION=(.+)$/)
  end

  # `config/deploy.yml`'s builder section carries a commented example of passing `RUBY_VERSION`
  # as a build arg, and it is the one place where the prefixed spelling is not merely redundant
  # but wrong: the value lands in `ruby:$RUBY_VERSION-slim`, and `ruby:ruby-4.0.6-slim` is not
  # an image — `docker manifest inspect` answers "no such manifest". Rails generated it
  # prefixed, so it was a landmine from the first commit, waiting for whoever uncommented it.
  #
  # Every occurrence is checked, at any comment depth. Both halves of that are load-bearing:
  # the block's own neighbours are commented `# #`, so a one-`#` pattern would let the bad value
  # come back under the file's own house style, silently; and reading only the first occurrence
  # would miss a real build arg written below the example.
  test "every RUBY_VERSION build arg in config/deploy.yml holds the bare reference" do
    declared = scan("config/deploy.yml", /^[\s#]*RUBY_VERSION:\s*(\S+)/)
    skip "config/deploy.yml declares no RUBY_VERSION build arg" if declared.empty?

    assert_equal [ REFERENCE ], declared.uniq
  end

  # The sixth copy, and the one every agent reads before every task — which is what makes a
  # stale value there worse than a stale value in a config file, not better. Any three-part
  # version written as "Ruby x.y.z" has to be the reference, so name a historical one the way
  # the paragraph below the icons section does: lowercase, or as the image tag it came from.
  test "CLAUDE.md names no Ruby version but the reference" do
    named = scan("CLAUDE.md", /\bRuby (\d+\.\d+\.\d+)/)

    assert_not_empty named, "CLAUDE.md names no Ruby version at all"
    assert_equal [ REFERENCE ], named.uniq
  end

  # The interpreter running this test. In CI and in the production image this is a tautology —
  # both install from `.ruby-version` — so what it guards is the local checkout, which is where
  # the drift happened and where it cost a wrong lint conclusion. A red suite is a louder answer
  # than a lint report that silently analysed the wrong language version. The corollary is that
  # moving to a newer patch release is a deliberate, coordinated edit of every declaration above
  # and not something a local `mise install` can do on its own — which is the point.
  test "the interpreter running the suite is the reference version" do
    assert_equal REFERENCE, RUBY_VERSION,
      "running Ruby #{RUBY_VERSION} but the repository pins #{REFERENCE} — a lint or a test " \
      "result from this interpreter cannot be compared with CI's"
  end

  private
    def scan(path, pattern)
      File.read(Rails.root.join(path)).scan(pattern).flatten
    end

    def declared_in(path, pattern)
      match = File.read(Rails.root.join(path))[pattern, 1]
      assert_not_nil match, "#{path} declares no Ruby version matching #{pattern.inspect}"
      match.strip
    end
end
