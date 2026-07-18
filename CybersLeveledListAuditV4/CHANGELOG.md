# Changelog

## v4.1.5

### Fixed

- **Leveled NPC (LVLN) entries never resolved.** LVLI and LVLN share the same
  entry struct, but the reference field is called `Item` in one and `NPC` in
  the other. v4.1.2 fixed `Item` only, so every NPC list still failed.

  On a full load order this produced 7,224 false `NULLREF` findings — 92% of
  them on `LChar*` lists — and inflated `ORPHAN` to 4,141, since nested NPC
  lists were never reference-counted. The giveaway in the data: across 16,106
  findings, every successfully resolved target was an item type (ALCH, LVLI,
  MISC, ARMO, AMMO, WEAP) and not one was an NPC.

  `EntryTarget` now tries `NPC` alongside `Item`, with the previous fallbacks
  retained.

  NPC records have no tier heuristic, so they return -1 and are skipped by the
  BALANCE and SPREAD checks, which already guarded for that.

- TAG KEY description for `DUPE` corrected — it has keyed on target, level and
  count since v4.1.4, but still described itself as matching target alone.

### Notes

- This release is the first where the injection cross-check ran against a real
  load order: 473 `INJECT`, 359 `CLOBBER`, 91 `LOSTINJECT` across 8,204 lists.
- `LOSTINJECT` findings from v4.1.4 remain valid — that check compares entry
  sets between overrides and does not depend on resolving targets.

## v4.1.4

### Fixed

- **Nested lists analysed once per parent.** A list reachable from several
  parents was fully re-analysed on each visit, so its findings were reported
  once per parent. `LL_Ammo_308Caliber` is nested under nine weapon lists, so
  its 4 entries produced 36 findings. `slVisiting` only guarded against cycles
  within a single path; a new `slWalked` set now ensures each list is analysed
  once per run. Reference counting still happens in the parent's loop, so
  orphan detection is unaffected.

- **DUPE no longer fires on vanilla quantity randomisation.** Bethesda lists
  routinely repeat the same item at different counts to vary how much you get -
  `LL_Ammo_308Caliber` holds the same ammo record five times at counts 2
  through 6. That was flagged as a duplicate. The check now keys on target
  **plus level plus count**, so only an exact repeat is reported, and the
  finding text explains that differing counts are normal.

## v4.1.3

### Fixed

- **False DUPE findings on nested lists.** The duplicate check used a global
  `slInjections` set that persisted for the whole run, but a nested list is
  visited once per parent that points to it. On the second visit every key was
  already present, so every entry was reported as a duplicate. A load order
  with 44 lists produced 92 DUPE findings, nearly all wrong.

  The check now uses a list-local set, created per visit and freed in a
  `finally`, so it only ever compares entries within the same list. The unused
  global has been removed.

### Notes

- The first run with working reference resolution confirms the v4.1.2 fix:
  `NULLREF` went from 257 to 0, nesting depth is detected, and item tiers are
  derived.
- Remaining `ORPHAN` findings on this test load order are the documented false
  positive: top-level vendor and NPC lists are referenced from NPC inventories
  and containers, which this script does not scan.

## v4.1.2

Fixes entry reference resolution for real, confirmed against actual xEdit
output rather than assumption. Supersedes the incorrect diagnoses in v4.0.2
and v4.1.1.

### Fixed

- **Entry target path.** The reference field is named `Item`, and it lives
  inside a child struct called `LVLO - Base Data`:

  ```
  Leveled List Entry
    LVLO - Base Data
      Level
      Item          <- target
      Count
      Chance None
  ```

  Every previous version looked for a field named `Reference`, at the wrong
  depth. All lookups returned nil, so every entry was reported `NULLREF`,
  no nesting was ever detected, and all lists were flagged `ORPHAN`.

  Why it took three attempts: `GetElementNativeValues(entry, 'LVLO\Level')`
  worked, because xEdit prefix-matches `LVLO` against `LVLO - Base Data`.
  Level and Count therefore read correctly while the reference silently
  failed, which pointed at handle lifetime and field naming rather than at
  path depth.

- xEdit paths quoted in finding messages updated to `LVLO - Base Data\...`, so
  the suggested fixes point where the field actually is.

### Added

- `EntryChanceNone` helper for the per-entry Chance None value, which is
  distinct from the list-level LVLD and was not previously read.

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
