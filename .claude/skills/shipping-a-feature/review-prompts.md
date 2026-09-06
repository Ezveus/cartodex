# Dispatch templates

Adapt, do not copy blindly. `<WT>` is the absolute path of the worktree, `<MAIN>` the shared
checkout. Every template names what the agent may write, because "read-only" stated once at the top
of a long prompt is not what an agent remembers at the end of it.

## Plan adversary (phase 3, before any code exists)

> Read `docs/superpowers/plans/<plan>.md` and the current test suite of `<MAIN>`. Do not write any
> file and do not implement anything.
>
> One question only: **of the decisions this plan makes, which would the existing suite fail to
> notice if they were implemented wrong?** For each one, name the test that looks like it covers
> it and say precisely why it would stay green — a fixture that holds no row of the new shape, an
> assertion on a rendered label the change does not alter, a count that both behaviours satisfy.
>
> You may run `bin/rails test <file>` and `bin/rails runner` to check a claim, and you should:
> a plan is fallible and its prescribed test code has carried real bugs here. Return a table:
> decision | test that appears to cover it | stays green because | what would actually catch it.

## Implementation lane (phase 5)

> Worktree `<WT>`, branch `worktree-<slug>`. [If isolated: first `cp <MAIN>/config/master.key
> config/master.key`, then `mise trust`, then `bundle install`.]
>
> Contract you implement against, frozen, do not renegotiate it: [constants, service signature,
> keyword names, column names, exact option labels].
>
> Files you may write: [allowlist]. Files you must not touch: [the other lanes' files].
>
> TDD: write the tests first, run them, **report the red output**, then implement and report the
> green. A test you never saw fail is not a test.
>
> [Isolated: run whatever you need.] [Shared worktree: **run no test at all** — the SQLite test
> database is shared with another agent and concurrent runs cascade into `SQLite3::BusyException`.
> Write the tests, say what you expect them to do, I will run them.]
>
> `bin/rubocop` on the files you wrote only — repo-wide it reports offenses CI never sees here.
> Code and comments in English; comments explain *why*. All views are Phlex (see the
> `phlex-architecture` skill); never write view logic in ERB.

## Neutral review (phase 7)

> Worktree `<WT>`, branch `worktree-<slug>`. Read `git diff master...HEAD` in full, plus
> `CLAUDE.md` and [the spec, if any].
>
> Standard review: correctness, reuse, simplification, cost, and conformity to this repository's
> stated conventions. **You may run anything** — the suite, `bin/rails runner`, `EXPLAIN QUERY
> PLAN`, a browser against `bin/dev`. Prove each finding with the command and its output; a
> finding argued in prose costs an hour to arbitrate, one that arrives with its reproduction costs
> ten minutes.
>
> Modify no file. Classify each finding blocker / discuss / cosmetic, with file:line. If an axis
> yields nothing, say so rather than inventing something.

## Adversarial review (phase 7)

> Same diff, same worktree. Your role is adversarial: **assume at least one real defect exists and
> find it.** Not typos — invariants.
>
> Instruct at least these, and say for each whether it holds, with the proof:
> - Hostile and malformed input on any public or anonymous route (`?x[]=`, `?x[a]=b`, absent,
>   empty, out of range). `PubliclyReachable` rescues only `RecordNotFound` and
>   `NotAuthorizedError` — anything else is a public 500.
> - **Second run, six weeks later, the source having moved.** [Include whenever the change writes
>   from an external source or accumulates rows.] Simulate it: run the import twice over a source
>   that changed between the two, and count what the database holds. The two worst defects found
>   on this repository were both "one run taken for the world" and both were invisible to every
>   unit test.
> - Concurrency: what holds the SQLite write lock, and for how long.
> - Does any page now state something the data does not support — a percentage over a mixed
>   population, a label whose sample is one row?
> - Which added tests are vacuous? Name them, and say what mutation leaves them green.
> - Rendering at 1400px and at 390px, measured as bounding boxes against `bin/dev`, not read off
>   the CSS.
>
> Verify every accusation with a command before writing it. Modify no file. Return proven defects
> only, ordered by severity.

## Domain review (phase 7, pick one)

> **Confidentiality / public surface** — who can now reach what, which policy answers, what a
> visitor sees that a member sees, and what a 404 versus a 403 discloses about existence.
>
> **Data truthfulness** — every figure the page prints: over which population, and does its
> heading say so.
>
> **Concurrency and write locks** — what work happens inside a transaction, and what could take
> the write lock across a network call.

## Sabotage (phase 6)

> Worktree copy, isolated — break whatever you like, nothing is kept. For **each** test added by
> this branch, apply one minimal plausible mutation to the implementation it claims to cover, run
> that test alone, and record whether it goes red. Restore between mutations.
>
> Return: test | mutation | red? | output. Call out every test that stays **green** under its
> mutation — that is decoration, and it needs rewriting, not a comment. Also say when a mutation
> proved something different from what the code's comment claims: the comment is then wrong too.
