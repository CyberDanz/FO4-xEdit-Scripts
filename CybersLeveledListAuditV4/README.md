# Cyber's Leveled List Auditor v4

**by CyberDanz**

An xEdit (FO4Edit) script that audits Fallout 4 leveled lists for structural
problems, balance outliers, and — the part most tools skip — **injected entries
that get silently lost to load order conflicts**.

It does not modify your plugins. It reads, analyses, and writes two report
files. Nothing else.

---

## Why this exists

Leveled lists are the most conflict-prone record type in a large Fallout 4 load
order, and the failure mode is quiet. If two mods both add weapons to
`LLI_Vendor_Weapons` and neither ships a patch, the plugin later in your load
order wins outright and everything the earlier one added simply never appears in
game. No crash, no error, no warning — the content is just gone.

Bashed Patch and Mator Smash exist to merge these automatically, and you should
still use them. This script answers a different question: *what is actually
happening in my lists right now, and what did I lose?* It tells you which plugin
injected what, which plugin dropped what, and which entries never made it into
the winning record.

It also catches the mundane breakage that accumulates in a long modlist —
zero-count entries, null references, circular nesting, lists so buried under
compounded Chance None rolls that nothing ever spawns.

---

## What it checks

Every finding is tagged and assigned a severity.

### Injection cross-check (the v4 addition)

Walks the full override chain of each list and diffs the entry set at every
step, attributing changes to specific plugins.

| Tag | Severity | Meaning |
|---|---|---|
| `LOSTINJECT` | CRITICAL | A plugin injected entries that are **absent from the winning override**. This content does not exist in your game. |
| `CLOBBER` | CRITICAL | A plugin dropped entries that were present before it in the load order. |
| `INJECT` | INFO | A plugin added entries. Baseline provenance, not a problem in itself. |

`LOSTINJECT` is the one that matters most. Sort the CSV by tag and start there.

### Structural integrity

| Tag | Severity | Meaning |
|---|---|---|
| `CYCLE` | CRITICAL | List is reachable from itself through nesting. Can hang or fail to resolve at runtime. |
| `NULLREF` | CRITICAL | Entry points at a record that does not resolve — missing master or unloaded plugin. |
| `COUNT` | CRITICAL | Entry count is zero. Rolling this entry produces nothing. |
| `COUNT` | INFO | Entry count above 20 — usually a typo on weapons or armor. |
| `EMPTY` | WARN | List has no entries at all. |
| `DEPTH` | WARN | Nesting deeper than 12 levels. |
| `DUPE` | WARN | Same target appears twice in one list, doubling its roll weight. |

### Reachability and probability

| Tag | Severity | Meaning |
|---|---|---|
| `CHANCE` | WARN | Chance None compounds across nesting to leave an effective spawn rate under 5%. |
| `LEVEL` | WARN | Entry level is 0 — available regardless of player level. |
| `LEVEL` | INFO | Entry level above 100 — effectively unreachable in normal play. |
| `ORPHAN` | INFO | No other leveled list references this one. **CSV only** — see note below. |

**On `ORPHAN`:** the script only scans leveled lists. Containers, NPC
inventories, and quest scripts are not examined, so a list flagged as an orphan
may still be referenced from somewhere it cannot see. On a full load order this
fires thousands of times and is mostly unactionable, so these findings are
written to the CSV only — the text report shows a count and this explanation.
Filter `Tag=ORPHAN` in the CSV to see them, and always confirm with Ctrl+F on
the FormID before deleting anything.

### Balance

| Tag | Severity | Meaning |
|---|---|---|
| `SPREAD` | WARN | Entry tiers span 6+ points within a single list — two rolls give wildly different power outcomes. |
| `BALANCE` | WARN | Entry tier exceeds the list's configured band — early access to late-game gear. |
| `BALANCE` | INFO | Entry tier below the configured band — underpowered filler. |

Tiers are derived automatically on a 0–10 scale. Weapons are scored on damage
per second weighted by ammo type and item value; armor on armor rating and
value; consumables, ammo, and misc items on value alone. Auto-derived tiers are
a heuristic and will misjudge unusual items — see the tier override file below
to correct them.

Balance checks only run for lists you have explicitly assigned a tier band. Without
`lltiers.txt`, everything else still works.

---

## Installation

Place `LeveledListAudit.pas` in your xEdit scripts folder:

```
<xEdit folder>\Edit Scripts\LeveledListAudit.pas
```

Optionally place `lltiers.txt` alongside it to enable balance checking.

Tested against FO4Edit 4.x. Requires no other dependencies.

---

## Usage

1. Launch FO4Edit and load your plugins. To audit the whole order, load
   everything; to audit a single mod, load just it and its masters.
2. In the left pane, select the plugin(s) you want audited — or expand a plugin
   and select its `Leveled Item` / `Leveled NPC` top-level group.
3. Right-click → **Apply Script**.
4. Choose **LeveledListAudit** and click OK.
5. When it finishes, check the Messages tab for the output paths.

Two files are written to your `Edit Scripts` folder:

- **`LeveledListAudit.txt`** — human-readable. Each finding is a block with the
  list, its origin plugin, the winning plugin, the full override chain, the
  exact xEdit path to the offending entry, an explanation, and a suggested fix.
- **`LeveledListAudit.csv`** — one row per finding, for sorting and filtering in
  a spreadsheet. Start by sorting on Severity, then Tag.

Plus, on every run:

- **`LeveledListAudit_<timestamp>.txt` / `.csv`** — an archive copy that is
  never overwritten. These accumulate, so you can compare any two runs later or
  keep a record from before a big load order change.
- **`LeveledListAuditDiff.txt`** — compares this run against the previous one.
  Lists what was RESOLVED (present last time, gone now) and what is NEW, with a
  net count. This is the fastest way to confirm a patch actually fixed what you
  intended.

The diff matches findings on tag, severity, list FormID, entry index and target
FormID — not on the sequential finding number, which shifts whenever anything
changes. On the first run there is nothing to compare against and the diff says
so.

Archive files accumulate indefinitely. Delete old ones whenever you like; the
script never reads them.

### Recommended workflow

1. Sort the CSV by Tag and read every `LOSTINJECT` first — that is content you
   are missing right now.
2. Then `CLOBBER`, checking each against the plugin name. A mod whose *purpose*
   is removing entries will trigger this legitimately.
3. Then the remaining CRITICAL rows — `NULLREF`, `COUNT`, `CYCLE`.
4. Build or update your Bashed Patch / Smashed Patch, adding any plugin that
   showed up under `LOSTINJECT` to your merge sources.
5. Re-run the script and confirm the `LOSTINJECT` findings are gone.

WARN and INFO findings are for reading at leisure. Many are deliberate design
choices by mod authors.

---

## Tier override file (optional)

Create `Edit Scripts\lltiers.txt` to correct auto-derived tiers and to define
which power band a list is supposed to contain. Without this file the script
skips balance checks entirely and everything else runs normally.

Format is one directive per line, space-separated. Blank lines are ignored.

```
# Assign a specific tier (0-10) to an item.
# Accepts EditorID or 8-digit FormID.
ITEM  MyModPlasmaRifle       9
ITEM  0801F3A2               7

# Assign a min/max tier band to a list.
LIST  LLI_Raider_Weapons     0  4
LIST  LLI_Gunner_Weapons     3  7
LIST  LLI_Vendor_Rare        7  10
```

Entries whose tier falls outside a list's band produce `BALANCE` findings. Use
`ITEM` lines whenever the auto-derived tier is obviously wrong — the heuristic
has no idea what a modded weapon is supposed to be worth.

---

## Reading the output

A finding block looks like this:

```
#47  [CRITICAL] LOSTINJECT
  List      : LLI_Vendor_Weapons [0004A2B1]
  Origin    : Fallout4.esm
  Winner    : SomeOtherWeapons.esp
  Chain     : Fallout4.esm -> MyWeapons.esp -> SomeOtherWeapons.esp
  Depth     : 0
  Path      : MyWeapons.esp
  Detail    : Entries carried by MyWeapons.esp are absent from the winning
              override (SomeOtherWeapons.esp): CustomRifle [0A001F3C] (L15|C1)
  Fix       : Create a patch loaded after both plugins containing the entries
              from each, or add MyWeapons.esp to your Bashed Patch / Smashed
              Patch merge sources.
```

`Chain` shows the full override sequence, left to right in load order.
`Path` shows either the nesting route taken to reach the list, or — for
injection findings — the plugin responsible. `Detail` names the specific entries
with their level and count.

---

## Known limitations

Read these before acting on output.

- **`CLOBBER` cannot distinguish intent.** A mod that deliberately strips
  entries looks identical to one clobbering by accident. Check the plugin name.
- **Diffs are sequential, not against vanilla.** Each override is compared to
  the state immediately before it. A plugin restoring something an earlier
  plugin removed will report as `INJECT`, which is accurate but can read oddly.
- **Nested lists are compared by FormID.** If two plugins point at *different*
  sublists that happen to contain the same items, that overlap is not detected.
- **Only leveled lists are scanned.** Container contents, NPC inventories, and
  quest-script insertions are invisible to this script. This is the main source
  of `ORPHAN` false positives.
- **Auto-derived tiers are heuristic.** They work reasonably for vanilla-like
  gear and poorly for anything unusual. Correct them in `lltiers.txt`.
- **ESL / light plugin FormIDs** rely on xEdit's `FixedFormID`. This should be
  correct, but verify against a light plugin you know before trusting output.
- **Runtime scales with load order size.** A full order with several thousand
  lists takes noticeably longer than a single plugin, since the injection pass
  walks every override of every list.

---

## Diagnostics

The [`diagnostics/`](diagnostics/) folder holds read-only scripts for
inspecting xEdit's actual record structure. Run `LLDiag.pas` if entry
resolution ever looks wrong — it prints the real field paths your xEdit build
uses, which is faster and more reliable than assuming them. See the
[diagnostics README](diagnostics/README.md) for why that matters.

---

## Contributing

Issues and pull requests welcome. When reporting a false positive or a wrong
finding, please include:

- The tag and severity
- The relevant block from `LeveledListAudit.txt`
- Which plugins are involved and their load order relative to each other
- Your xEdit version

If the script errors out, the xEdit Messages tab output is what I need.

### Forks

Fork it and build on it — that is what the MIT license is there for. You are
free to modify, extend, redistribute, and use this in your own projects,
including commercially, with no permission needed. The only requirement is that
the copyright notice and license text stay with the code.

If you build something useful on top of it, I would genuinely like to hear about
it. Open an issue or drop a link. Not required, just appreciated.

---

## Repository topics

For discoverability, this repo is tagged:

`fallout4` · `xedit` · `fo4edit` · `modding` · `pascal` · `leveled-lists`
· `fallout4-mods` · `modding-tools` · `load-order` · `conflict-detection`

---

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 CyberDanz.

## Credits

Written by CyberDanz for use with
[xEdit](https://github.com/TES5Edit/TES5Edit) by ElminsterAU and the xEdit team.
The Pascal scripting interface this builds on is their work.
