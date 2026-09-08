require "test_helper"

# The Ruby version is declared four times over — `.ruby-version`, `mise.toml`, the production
# `Dockerfile` and the devcontainer's — and until this test existed nothing made the four agree.
# They had already drifted: `.ruby-version` said 3.4.1 while `mise.toml` said 4.0.1, so every
# local `bin/rubocop` analysed as Ruby 3.4 on a Ruby 4.0.1 interpreter and a lint result could
# not be compared with CI's. Nothing about that was visible — no command failed, no file
# complained, and the two spellings of the same fact simply answered different questions.
#
# `.ruby-version` is the reference, because it is what the pipeline installs from: all six of
# `.github/workflows/ci.yml`'s jobs say `ruby-version: .ruby-version`, so whatever it holds is
# the version the five gates and the deploy actually run under. Every other declaration is a
# copy that has to follow it.
class RubyVersionTest < ActiveSupport::TestCase
  REFERENCE = File.read(Rails.root.join(".ruby-version")).strip.delete_prefix("ruby-").freeze

  # A bare `4.0.1` and not `ruby-4.0.1` in `.ruby-version` would still install correctly —
  # setup-ruby and mise both accept either — but the Dockerfiles interpolate their `ARG` into an
  # image tag (`ruby:$RUBY_VERSION-slim`), where the prefix is not a spelling variant: it names
  # no image. Pinning the shape here is what lets the three comparisons below be string equality.
  test "the reference is a ruby-prefixed three-part version" do
    assert_match(/\Aruby-\d+\.\d+\.\d+\n?\z/, File.read(Rails.root.join(".ruby-version")))
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

  # The interpreter running this test. In CI and in the production image this is a tautology —
  # both install from `.ruby-version` — so what it guards is the local checkout, which is where
  # the drift happened and where it cost a wrong lint conclusion. A red suite is a louder answer
  # than a lint report that silently analysed the wrong language version.
  test "the interpreter running the suite is the reference version" do
    assert_equal REFERENCE, RUBY_VERSION,
      "running Ruby #{RUBY_VERSION} but the repository pins #{REFERENCE} — a lint or a test " \
      "result from this interpreter cannot be compared with CI's"
  end

  private
    def declared_in(path, pattern)
      match = File.read(Rails.root.join(path))[pattern, 1]
      assert_not_nil match, "#{path} declares no Ruby version matching #{pattern.inspect}"
      match.strip
    end
end
