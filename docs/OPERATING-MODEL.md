# Operating model for a stable cadence

How to keep a fleet of coding agents focused so features reach production at a predictable rhythm: few lead decisions, little
rework, no silent stalls. Every rule has a check a script can run. Derived from one week of a running fleet (numbers below,
with the method). Tools referenced: `fleet-feed` (queues only slices with unchecked items and a publish-mode paragraph; the full seat-ready check below is yours to script),  `fleet-refill`, `fleet-batch-land`,
`fleet-preflight`, `fleet-cred-check`. Rules that are lessons rather than design live in `docs/LESSONS.md` ("Cadence rules").

## What we measured (and how)
Window: 7 days, last day incomplete. Sources: the dispatch ledger, seat reports by modification time, the main branch's history and
reflog, raw gate logs, the refill daemon's log. Commands were scripted and re-runnable against a frozen main tip; percentiles use
linear interpolation. Counts are fleet-wide, no per-project data.
- **Code landings** (unique non-merge commits touching code paths, bean-only commits excluded): 1,289 in 7 days, 87-395 per day,
  around 3.3 push bursts per hour around the clock. Code throughput, not feature or deployment throughput.
- **Dispatch noise**: 1,395 dispatches in one day, 88% of them carrying no work item (queue fix items, standing hunts); 79 distinct
  work items touched. Dispatches per landed item: about 18. Assignments per day grew 5 -> 98 -> 303 -> 917 -> 1,395 in a week while
  commits per day stayed flat.
- **Claims versus main**: of 139 seat reports that named a code commit, 78 (56%) still had at least one named commit SUBJECT missing
  from the main branch one hour later; a bare "READY" headline missed the hour 89% of the time; a work item assigned a third time
  across seats missed it 85% of the time. Matching by SHA would have failed 20 reports that were fully landed (rebases change SHAs):
  always match by subject.
- **Lead time** (first assign -> first landed code, newly introduced items only): n=25, median 208 h, p90 434 h. Small and
  left-censored (140 landed items, 53 with no assign record, 37 landed before their recorded assign): treat it as "days", not a KPI.
- **Gate**: the same pre-push hook costs 44-66 s when its pass cache hits and about 1,000 s when the full related-test set runs;
  build plus static checks about 40 s. At ~80 pushes a day a per-push gate has worst-case utilisation above 0.9.
- **Not measurable**: idle time (the ledger had no finish events and reports are overwritten), whole-item completion and
  deployment lead time. Add those events before arguing about them.

## Work unit and "seat-ready"
One assignment = one SLICE: one commit set, one owner, finishable in about 2 hours, at most ~8 files and ~400 changed lines, with a
failing test first and an acceptance command. A work item is a list of slices; a seat holds one slice at a time.
A slice is seat-ready only if all of these are machine-true (script them; run them before a slice is queued):
1. the item is open on the main branch and `git log origin/main --grep=<item>` does not already show the slice's subject;
2. the slice names its files, a failing test and an acceptance command;
3. it contains nothing that needs the operator (applying a migration, a credential, live data, a browser check, a decision);
4. every slice it depends on is on the main branch by subject;
5. the files it names exist on the main branch (or are marked new).
Check: assignments that end BLOCKED within 10 minutes (target 0). Refuse dispatches that carry no ready-checked item id.

## Flow and who owns each arrow
assign -> build (branch per item, commit per slice) -> verify (build and related tests pasted, revert-test-restore) -> cross-model
review that runs the code -> publish (direct or lander, one mode) -> deploy (window) -> verify (metric recorded). Each arrow has one
owner and one machine-readable marker (task file, report with REBASED/VERIFIED lines, approval marker, ready/landed records, deploy
state, a measured section). The lead appears at priorities, operator decisions, credentials and the deploy go; everything else is a
state change a daemon performs. One report per READY slice, not per sub-step.

## WIP limits (enforced by the daemons, not by reminders)
- Per seat: one slice in build, plus one waiting for review or landing; the next slice starts only when the previous is landed or
  READY. The refill daemon never feeds a seat that has a task file, an unlanded branch, or a bean-named commit not on main younger
  than 90 minutes (`HOLD` in its log): a quiet screen is not idle.
- Per item: one owner. An item assigned a third time is escalated with the blocker recorded, not re-dispatched.
- Open items in flight <= the number of live seats. Seats on a harness with no quota are excluded by configuration.
- READY queue <= 6; if it is longer, or the oldest READY is older than 40 minutes, stop assigning and alert: landing is the
  bottleneck, not coding.
- Lead: <= 3 open decisions; one older than 30 minutes goes to the operator's digest. The lead dispatches nothing by hand.

## One owner per coherent change
Default: one owner for the whole change, split into commits. Slice across seats only if the files are disjoint, every slice builds
and passes its tests alone on the main branch, and the slice that touches a shared contract (3+ importers, a schema, a prompt or
rubric) is done and LANDED first by the strongest seat; dependent slices are not dispatchable until it is on the main branch. Weak
or small-budget seats get small, self-contained slices, never the hard part. Check: dependent slices started before their
prerequisite landed = 0.

## Publication mode: written once, read by every brief
One file (`DROVER_PUBLISH_MODE_FILE`, default `~/.config/drover/publish-mode`) holds `direct` (seats land their own tested commits
through the pre-push hook; the default) or `lander` (seats report READY and never push; `fleet-batch-land` lands). Generated briefs
take their LANDING paragraph from it; nobody hand-writes "do not push". `fleet-preflight` is DEAD if the mode says lander while the
lander is not installed and enabled, or says direct while the lander's enable marker exists (the hook would refuse the seats).
Choose the batch lander when pushes are frequent and the gate is slow (it caps gate runs, isolates a failing branch and proves
ancestry per commit); choose direct when the lander is not yet running. A single "lander seat" is rejected: an agent is a slower and
more interruptible lander than a script and recreates the lead bottleneck.

## Definition of done: three levels, by subject
- L1 LANDED: `git log origin/main --grep=<item>` shows the slice subjects, and the lander's record (if used) holds only proven
  commits. A seat's "pushed" or "closed" is a claim.
- L2 DEPLOYED: the production version endpoint contains the L1 commits, inside a deploy window.
- L3 MEASURED: the acceptance number is recorded with its source. User-visible items complete at L3; internal ones may complete at L1.
Landing is enforced by three machines (`fleet-done` refuses unlanded finished work in direct mode, the refill audit nudges at 30 and
alerts at 60 minutes, `fleet-preflight` turns the alert into DEAD; see LESSONS).
Production may not lag the main branch: `fleet-preflight` is DEAD when code commits older than 90 minutes are undeployed.

## Rhythm
- Continuous: refill and feed ticks (60 s), lander tick (3 READY or 20 min), a heartbeat in every daemon log (older than 10 minutes =
  dead). Every daemon tick has a watchdog.
- Daily: an automatic standup with L1/L2/L3 counts, READY age, stalled seats (no commit and no task for 45 minutes), credentials and
  open decisions. Credentials are checked at start and end of day and before each deploy; short-lived cloud sessions are refreshed
  then, never mid-delivery.
- Deploy: two windows a day, only when nothing is mid-render or mid-migration and L1 has a new item; a hotfix opens a window with
  the same checks.
- Weekly: a retro on numbers (L3 items, dispatches per landed item, BLOCKED within 10 minutes, review rounds per item, READY age p90,
  pushes per landed item). A rule changes only if a metric moved, and ships with its check.

## First changes, in order
1. Make the publication mode explicit and add `fleet-preflight`. 2. Refuse dispatches without a ready-checked item.
3. Define idle as "no task, no unlanded commits, screen unchanged" and re-queue unclaimed work after 90 minutes.
4. One report per READY slice. 5. Add the L1/L2/L3 columns to the standup (needs a clean ledger).
