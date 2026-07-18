# Changelog

## v4.1.1

Fixes the real cause of the mass NULLREF problem. v4.0.2 misdiagnosed it.

### Fixed

- **Entry reference resolution.** `EntryTarget` used
  `ElementBySignature(entry, 'LVLO')`, which looks for a child element named
  LVLO. In FO4 the entry element *is* the LVLO struct — `Level`, `Count` and
  `Reference` are fields directly inside it, with no nested child. So the lookup
  returned nothing and `LinksTo` failed on every entry, producing hundreds of
  false `NULLREF` findings, no nesting detection, and every list flagged
  `ORPHAN`.

  `Reference` is now read directly, with fallbacks to the older paths for other
  xEdit versions and record layouts. `Level` and `Count` route through matching
  helpers.

  The giveaway: Level and Count read correctly all along, which meant the entry
  handle was valid and only the reference lookup was wrong. v4.0.2 blamed stale
  handles and changed the pass structure — a real improvement, but not the bug.

### Added

- Sanity check in the summary. If no entry resolves and no list references
  another, the report says the results are untrustworthy and explains the likely
  causes, instead of presenting hundreds of bogus findings as fact.

## v4.1.0

### Added

- **Timestamped archive output.** Every run now also writes
  `LeveledListAudit_<timestamp>.txt` and `.csv`, which are never overwritten.
  Build a history without losing earlier runs.
- **Stable latest-run path retained.** `LeveledListAudit.txt` / `.csv` still
  always hold the most recent run, so you have one path to open.
- **Run comparison report.** `LeveledListAuditDiff.txt` compares this run
  against the previous latest CSV and lists findings under RESOLVED (present
  before, gone now) and NEW (not present before), with a net count. Findings
  are matched on tag, severity, list FormID, entry index and target FormID —
  not on the sequential ID, which shifts between runs.
- `SafeStamp`, `SplitCsv`, `FindingSig` helpers. The timestamp is built from
  `DateToStr`/`TimeToStr` rather than `FormatDateTime`, which is not confirmed
  present in the interpreter.

### Notes

- The diff reads the previous CSV before overwriting it, so the first run
  reports that there is nothing to compare against.
- A finding whose level or count changed but which is otherwise the same entry
  counts as unchanged, since those fields are not part of the signature.

## v4.0.2

Fixes a bug that made v4.0.1 output meaningless on a real load order.

### Fixed

- **Stale element handles.** `Process` stored `IInterface` handles in a
  `TStringList` and re-resolved them in `Finalize` via `ObjectToElement`. xEdit
  only guarantees handles remain valid inside the `Process` callback, so by the
  time `Finalize` ran, every `LinksTo` resolved to nothing. Symptoms: nearly
  every entry reported as `NULLREF`, every list reported as `ORPHAN`, and
  `Max nesting depth: 0` regardless of actual nesting.

  All analysis (`WalkList`, `SpreadCheck`, `InjectionCheck`) now runs inside
  `Process` while handles are live. `Finalize` only emits the orphan pass, from
  FormIDs and EditorIDs captured earlier, and writes the output files.

### Changed

- Report header moved from `Finalize` to `Initialize` so it precedes findings.
- `Process` relocated below its callees — the interpreter has no forward
  declarations.
- Added `slListNames` to carry list EditorIDs into the orphan pass.

## v4.0.1

Compatibility fixes for xEdit's Pascal interpreter (JvInterpreter), found on
first live run. No behaviour changes.

### Fixed

- `BoolToStr` is not available in the interpreter and aborted the script in
  `Finalize` while writing the report header. Replaced with an explicit
  `if`/`else`.
- `SameText` replaced with an `Uppercase` comparison in the injection pass.
- All `Pred(X)` loop bounds rewritten as `X - 1`.

## v4

### Added

- **Injection cross-check pass.** Walks the override chain of every leveled
  list and diffs entry sets at each step, attributing additions and removals to
  specific plugins. Three new tags:
  - `LOSTINJECT` (CRITICAL) — entries a plugin injected that are absent from the
    winning override. This is content silently missing from the game, and the
    single most common leveled list failure in a large load order.
  - `CLOBBER` (CRITICAL) — a plugin dropped entries present before it in the
    load order.
  - `INJECT` (INFO) — a plugin added entries. Provenance baseline.
- Tag key printed in the report header, explaining every tag in one place.
- Entry identity now keys on `FormID|Level|Count`, so two plugins adding the
  same item at different levels are tracked separately rather than collapsed.
- Name cache populated during the injection pass, so findings label entries by
  EditorID rather than bare FormID where possible.

### Fixed

- **Inconsistent record identity.** `Process()` indexed whatever record
  instance xEdit handed it, while `WinningPlugin()` reported a different one —
  output could contradict itself when auditing multiple plugins. `Process()`
  now anchors on `MasterOrSelf`, and `WalkList` / `SpreadCheck` resolve the
  winning override internally.
- **False `BALANCE` warnings.** The `tier > thi` check fired when `thi` was -1,
  meaning any list without a configured band produced spurious findings. Now
  guarded.
- **Potential exception in `slVisiting.Delete`.** Called with an unguarded
  `IndexOf` result, which would raise if the key was ever absent. Now checked.
- Empty-path handling in `WalkList` no longer produces a leading `>` separator
  on top-level lists.
- Null guards added to `KeyOf`, `IsLeveled`, `TierOfItem`, `DeriveTier`, and the
  tier lookup helpers.

### Changed

- LVLO target resolution factored into a shared `EntryTarget()` helper; the
  fallback logic was previously duplicated in three places.
- `EditorID` falls back to `Name` for records with no editor ID, in both report
  output and the name cache.
- Report header severity key expanded to note that CRITICAL now includes silent
  content loss, not only runtime breakage.

## v3

- Structured diagnostic logging with provenance, severity, and actionable fix
  text routed through a central `Log` procedure.
- Dual output: human-readable `.txt` and sortable `.csv`.
- Tag set: `CYCLE`, `NULLREF`, `COUNT`, `LEVEL`, `CHANCE`, `DEPTH`, `EMPTY`,
  `DUPE`, `SPREAD`, `BALANCE`, `ORPHAN`.
- Auto-derived item tiers on a 0–10 scale, with optional manual overrides via
  `lltiers.txt`.
- Cumulative Chance None tracking across nesting depth.
- Cycle detection and depth limiting.
