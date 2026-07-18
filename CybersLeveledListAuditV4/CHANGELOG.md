# Changelog

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
