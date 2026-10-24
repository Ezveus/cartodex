require "test_helper"

# The JavaScript unit tests (test/javascript/, run by `npm test`) import controllers from npm's
# copy of Stimulus, while the app serves the copy the stimulus-rails gem vendors. Nothing ties the
# two together but this file: a dependabot bump of the gem would otherwise leave the tests
# exercising one Stimulus and production running another, with every test still green.
#
# It is a Minitest test and not a Vitest one so that it runs in the `test` job, where Bundler has
# resolved the gem, and fails on the very pull request that moves the gem. It sits at the root of
# `test/` beside ruby_version_test.rb for the reason given there: it answers to configuration
# files, not to anything under `app/`.
class JavascriptToolchainTest < ActiveSupport::TestCase
  # importmap pins `stimulus.min.js`, which carries no version at all; the banner is in the
  # unminified `stimulus.js` the same gem release ships beside it. Read from the gem Bundler
  # actually loaded, so the reference follows Gemfile.lock rather than a number written here.
  # The npm package's own banner is no substitute: the 3.2.2 release on npm still says 3.2.1.
  VENDORED = begin
    path = File.join(Gem.loaded_specs.fetch("stimulus-rails").full_gem_path, "app/assets/javascripts/stimulus.js")
    File.read(path)[/^Stimulus (\d+\.\d+\.\d+)$/, 1]
  end

  test "the stimulus-rails gem vendors a Stimulus whose version can be read" do
    assert_match(/\A\d+\.\d+\.\d+\z/, VENDORED.to_s,
      "no `Stimulus x.y.z` banner in stimulus-rails' stimulus.js — the gem changed its layout, " \
      "and this test has to learn where the version lives now")
  end

  # Exact, because a range would let `npm install` pick a version the guard below never compared.
  test "package.json pins the Stimulus the gem vendors, exactly" do
    assert_equal VENDORED, package_json.dig("devDependencies", "@hotwired/stimulus"),
      "package.json's @hotwired/stimulus must be exactly the #{VENDORED} that stimulus-rails " \
      "vendors — bump it in the same pull request as the gem"
  end

  # Every package, not only Stimulus: a range lets the lock move under a `npm install` nobody
  # reviewed, and the lock is the only record of what CI ran.
  test "package.json pins every devDependency to an exact version, and has no runtime dependency" do
    package_json.fetch("devDependencies").each do |name, version|
      assert_match(/\A\d+\.\d+\.\d+\z/, version, "#{name} is pinned to #{version.inspect}, not an exact version")
    end
    assert_nil package_json["dependencies"], "package.json is dev/test only: importmap serves the app"
  end

  # What `npm ci` installs is the lock's version, not package.json's; `npm ci` refuses a lock that
  # disagrees with package.json, but nothing stops a hand-edited package.json being committed
  # without regenerating the lock.
  test "package-lock.json installs the Stimulus the gem vendors" do
    assert_equal VENDORED, package_lock.dig("packages", "node_modules/@hotwired/stimulus", "version")
  end

  # mise.toml is the one declaration of the Node version: a developer's `mise` reads it and so does
  # every CI job, through setup-node's `node-version-file`. A job given a literal version instead
  # would test on a Node nobody else runs — the drift ruby_version_test.rb exists to stop.
  test "mise.toml declares a three-part Node version" do
    assert_match(/^node\s*=\s*"\d+\.\d+\.\d+"$/, File.read(Rails.root.join("mise.toml")))
  end

  test "every CI job that installs Node reads its version from mise.toml" do
    steps = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
    node_steps = steps.select { |step| step["uses"].to_s.start_with?("actions/setup-node@") }

    assert_not_empty node_steps, "no job in ci.yml sets up Node, so nothing runs `npm test`"
    node_steps.each do |step|
      assert_equal({ "node-version-file" => "mise.toml" }, step.fetch("with", {}).slice("node-version", "node-version-file"))
    end
  end

  # A seventh CI job would be useless without this: the deploy runs only once every job it needs
  # has passed, and a job it does not need is a check a red build can deploy past.
  test "the deploy waits for the JavaScript tests" do
    assert_includes workflow.dig("jobs", "deploy", "needs"), "test_js"
    assert_includes workflow.dig("jobs", "test_js", "steps").map { |step| step["run"] }, "npm test"
  end

  # Stimulus is left to the gem's bundler pull requests (see the guard above); everything else in
  # package.json gets dependabot's npm pull requests like the gems and the actions do.
  test "dependabot updates npm, except the Stimulus that follows the gem" do
    updates = YAML.safe_load_file(Rails.root.join(".github/dependabot.yml")).fetch("updates")
    npm = updates.find { |update| update["package-ecosystem"] == "npm" }

    assert_not_nil npm, "dependabot.yml has no npm entry"
    assert_equal [ "@hotwired/stimulus" ], npm.fetch("ignore", []).map { |rule| rule["dependency-name"] }
    assert_equal %w[bundler github-actions npm], updates.map { |update| update["package-ecosystem"] }.sort
  end

  test "node_modules is ignored by git" do
    assert system("git", "-C", Rails.root.to_s, "check-ignore", "-q", "node_modules/vitest/package.json"),
      "node_modules/ is not in .gitignore"
  end

  # Vitest cannot guard its own `include`: a narrower glob stops collecting the very test that would
  # complain (measured: `*/*.test.js` ran 3 of 7 files, green, exit 0). config.test.js proves every
  # file matches this glob; this pins the glob from outside it.
  test "vitest collects every test under test/javascript" do
    assert_equal [ "test/javascript/**/*.test.js" ],
      File.read(Rails.root.join("vitest.config.js"))[/^\s*include:\s*\[(.*)\]/, 1].to_s.scan(/"([^"]+)"/).flatten
  end

  private
    def package_json
      JSON.parse(File.read(Rails.root.join("package.json")))
    end

    def package_lock
      JSON.parse(File.read(Rails.root.join("package-lock.json")))
    end

    def workflow
      YAML.safe_load_file(Rails.root.join(".github/workflows/ci.yml"))
    end
end
