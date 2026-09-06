---
name: shipping-a-feature
description: Use when a ticket, feature, bug fix or refactor in this repository is to be carried end to end, and whenever a request asks for autonomy, for hypotheses to be tested rather than inferred, for neutral and adversarial subagent reviews, or for parallel subagent implementation. Not for answering a question about the code, a one-line correction, or debugging a single failure.
---

# Shipping a feature in cartodex

The pipeline below is what this repository already practises, written down so that it happens the
same way twice. Three baseline runs of the same request produced 0, 2 and 3 implementation agents,
one spec out of three, and one plan that had two agents running `bin/rails test` against the same
SQLite file. The value here is not the steps — a capable agent finds most of them — it is that the
load-bearing ones stop being optional.

**Core principle:** every claim you make about this system must come from output you read. Not from
a docstring, not from a comment, not from the plan you just wrote.

## Phases and their gates

Each phase has a gate. Do not enter the next phase until the gate produced output you read.

### 0. Frame, then ask once — or not at all

Read the ticket. Fan out **read-only** recon agents (`Explore`, or `general-purpose` told to write
nothing) to establish the facts the request depends on: who reads the thing you are changing, what
already exists that you should reuse, which tests pin it.

Recon regularly finds that the request names something that does not exist, or that two readings
produce different deliverables. **That is the one moment to ask.** One message, the questions
together, then go. A design ambiguity discovered in recon and reported only in the final message is
a deliverable built on a guess; a question asked after the code exists is a question asked too late.

Ambiguity that does not change the shape of the deliverable is not a question — state the
assumption in the spec and continue.

**Gate:** the facts are in your context as file:line or command output, and either no question
remains or the answer to it is in.

### 1. Measure — inference is not evidence

The only written description of an external source in this repository was wrong on two points, each
of which silently corrupts data. `require "csv"` fails under Bundler here and no file says so.
`bin/rubocop` reports ~159 offenses locally that CI never sees.

Anything decided by a fact goes and gets the fact:

| Question | What answers it |
|---|---|
| What does that page actually contain? | Fetch it. Count the rows. |
| Does that query still use the index? | `EXPLAIN QUERY PLAN` through `bin/rails runner` |
| Does the layout hold? | `bin/dev` + chrome-devtools, **bounding boxes**, both widths |
| Is that gem loadable? | `bundle exec ruby -e 'require "x"'` |
| What does the data look like? | `bin/rails runner` against the dev database |
| Is that how this repository does it? | Count it — `gh pr list`, `git log`, a grep. Two of the last twelve is not a convention |

**Gate:** every number that will appear in the spec, the commit message or the PR body exists as
command output you have seen.

### 2. Spec — only when the decision outlives the diff

Write `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md` (English) when the change adds a table,
a column, an external source, a public surface, or a rule a later reader could reasonably undo.
Otherwise write none — and **say so out loud**, with the reason. A silently skipped spec and a
deliberately skipped spec look identical in the repository and are not the same decision.

**Gate:** the spec names its measurements, or you have stated why there is no spec.

### 3. Plan, then attack the plan before it exists in code

Write the plan into `docs/superpowers/plans/`. Then dispatch **one adversarial agent against the
plan itself**, with exactly one mandate:

> Of the decisions this plan makes, which would the existing test suite fail to notice if they
> were implemented wrong? Name them, and name the test that looks like it covers each one and
> does not.

None of the three baseline runs did this, and it is where the cheapest defects are found. A test
asserting "divisions are ordered junior, senior, masters" over a fixture holding three divisions
stops guarding anything the day a fourth value exists, and stays green forever. That agent's list
**is** the list of tests to write.

**Gate:** the "would stay green" list exists and every entry has a test assigned to it.

### 4. Worktree

```bash
git worktree add -b worktree-<slug> .claude/worktrees/<slug> master
cp <main-checkout>/config/master.key .claude/worktrees/<slug>/config/master.key
cd .claude/worktrees/<slug> && mise trust && bundle install && bin/rails db:test:prepare test
```

`master.key` and `mise trust` come **before** `bundle`; nothing boots otherwise, and no file in the
repository records it. Never `cd` back to the shared checkout — the Bash tool's directory persists
and every later command is refused, including the `cd` that would fix it. Read the other checkout
by absolute path.

**Gate:** the baseline run count is written down. "1250 runs, 0 failures" is what proves, later,
that your own tests actually executed.

### 5. Implement in parallel — against a frozen contract

Parallelise on **disjoint file sets**, not on ambition. Before dispatching, freeze what the agents
share: constant names, service signature, keyword names, column names. Agents consume a contract;
they do not negotiate one across a fan-out.

Give each agent an explicit allowlist and an explicit do-not-touch list, and require TDD with both
outputs reported (red, then green).

**One test database per worktree.** `storage/test.sqlite3` is shared, and two agents running
`bin/rails test` in one worktree cascade into `SQLite3::BusyException` — roughly a hundred failures
that do not exist. Pick one per agent:

- `isolation: "worktree"` — the agent gets its own copy and may run anything. It must do
  `master.key` + `mise trust` + `bundle install` itself, and its dev database starts empty.
- **Write-only** — "do not run any test, I will run them", and you run them yourself, serialised.

The lane split that works: one server lane (model, service, controller, routes, request tests), one
view lane (Phlex components, CSS, system tests). Below roughly two lanes, dispatching costs more
than it returns — say so rather than inventing a third.

**Gate:** you integrated the lanes and ran the suite yourself. An agent's green is not your green.

### 6. Verify — six commands and two things no command covers

```bash
bin/rails test                                     # run count > the baseline you recorded
bin/rails test:system
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system
bin/rubocop <the files you wrote>                  # never repo-wide, see Traps
bin/brakeman --no-pager
bin/importmap audit
```

**Sabotage every new test.** Break the mechanism the test claims to hold, watch it go red, restore,
watch it go green, report both. A test that survives a plausible mutation is decoration — rewrite
it, do not annotate it. Around forty sabotages on one branch found three tests that discriminated
nothing.

**Open the browser.** Reviews read code and cannot see rendering. One real blocker — a note that
became a sibling flex item and grew a row from 29px to 64px at 390px — was invisible to every test
in the repository and to a text assertion, because the element rendered either way, in the wrong
place. Any element added to a `Ui::DataTable` cell, and any layout change, is checked under 768px
by **geometry**, not by text.

**Gate:** all six green, the sabotage table exists, and the rendered page was looked at.

### 7. Three reviews, and they may run code

Dispatch in parallel:

1. **Neutral** — correctness, reuse, simplification, conformity to `CLAUDE.md`.
2. **Adversarial** — assume at least one real defect exists and find it.
3. **Domain**, chosen from what the diff touches: confidentiality and public surface; concurrency
   and write locks; truthfulness of what the page states.

Two reviews is the baseline behaviour and it is one short. Historically the third found real
defects the other two missed.

**Every review may execute code** (`bin/rails runner`, the suite, a browser). A blocker that
arrives with its reproduction is fixed in ten minutes; the same blocker argued in prose is debated.
No review edits a file.

The adversarial mandate always includes, for anything that writes from an external source or
accumulates rows: **"what happens on the second run, six weeks later, if the source has moved?"**
Four implementation agents delivered a fully green suite over two defects that were both the same
mistake — taking one import run for the world — and neither is visible to a unit test, because both
require simulating time.

Templates: `review-prompts.md` in this directory.

**Gate:** three reports, each finding carrying its proof.

### 8. Triage — fix defects, escalate decisions

- **A technical defect with a reproduction** → fix it. That is what autonomy is for.
- **Anything that moves a product decision, the shape of the deliverable, or something already
  decided explicitly** → present the finding, your analysis and a recommendation, and wait.

Do not perform agreement with a review. A finding you cannot reproduce is a finding you say you
could not reproduce.

Findings land in their own commit: `Close the review's findings on <subject>`, body explaining each.

**Gate:** every finding is fixed, rejected with a written reason, or in front of the owner.

### 9. Document what does not reread from the code

Add to `CLAUDE.md` the decisions a later reader would otherwise undo, and **verify each sentence
against the file it describes** — a `CLAUDE.md` that lies is worse than one that says nothing.

Commit messages here are prose that explain *why*, carrying the measurement. PR body: what it does,
the non-obvious decisions with their numbers, the verification figures (run counts both sides of
the breakpoint, rubocop, brakeman), and what is deliberately out of scope.

### 10. Stop before the merge

Merge and the Kamal deploy are the owner's, always. Write the handoff in **French** to
`./tmp/handoff-YYYY-MM-DD-<slug>.md`: what shipped, the decisions that cost the most to undo, the
traps hit, what is still open.

Only once a PR is **merged and deployed** does the post-merge cleanup routine run (worktree, local
and remote branch, host backups, dev database).

## Traps that have actually cost time here

| Trap | What to do |
|---|---|
| `bin/rubocop` repo-wide reports offenses CI never sees (mise resolves Ruby 4.0.1) | Lint the files you wrote |
| `bin/rails test:system` ignores file arguments and runs everything | `bin/rails test test/system/x_test.rb` for the fast loop |
| Two agents, one worktree, one `test.sqlite3` | Serialise, or `isolation: "worktree"` |
| A fresh worktree has no `master.key`, an untrusted `mise.toml`, an empty dev database | Do all three before `bundle` |
| `db:rollback` refuses (multi-database) | `bin/rails db:rollback:primary` |
| `format(…)` inside a Phlex component raises `ArgumentError` | `Kernel.format` |
| Fixtures skip callbacks | Spell out `*_normalized`, `decks.key` by hand |
| Fixtures already hold rows of the thing you are counting | Compare id sets, never counters |
| A restored production dump refuses every destructive task | `bin/rails db:environment:set RAILS_ENV=development` |

## Red flags — stop and go back a phase

- "The docstring says…", "presumably", "should be" — go and measure it.
- Citing a convention of this repository that you never counted — the two most recent examples
  are not the rule, and inventing a rule is the same failure as inventing a fact.
- "The suite is green" as the end of verification — green is the floor; sabotage is the test.
- Two implementation agents whose file lists overlap, or who both run tests in one worktree.
- A plan whose tests were never checked against "what would stay green".
- Two reviews instead of three, or a review that was not allowed to run anything.
- Applying a review finding that reverses something the owner decided.
- A question you are saving for the final message that should have been asked after recon.
- Reporting completion with a number you did not read out of a command.
