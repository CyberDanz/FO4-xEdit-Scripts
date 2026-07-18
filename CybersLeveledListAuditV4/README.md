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
| `ORPHAN` | INFO | No other leveled list references this one. |

**On `ORPHAN` false positives:** the script only scans leveled lists. Containers,
NPC inventories, and quest scripts are not examined, so a list flagged as an
orphan may still be referenced from somewhere it cannot see. Always confirm with
Ctrl+F on the FormID before deleting anything.

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

Place `CybersLeveledListAuditV4.pas` in your xEdit scripts folder:
