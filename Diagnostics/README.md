# Diagnostics

Read-only scripts for inspecting xEdit's actual record structure. They exist
because the main auditor was written three times against assumed field names
and was wrong every time — these settle the question in one run instead.

None of them modify plugins. They read, print, and write a text file.

---

## Why you would need these

Leveled list entry layout is not stable across games or xEdit versions. In
Fallout 4 under xEdit 4.1.5q, the reference field lives at:

```
Leveled List Entry \ LVLO - Base Data \ Item     (LVLI, leveled item)
Leveled List Entry \ LVLO - Base Data \ NPC      (LVLN, leveled NPC)
```

Two things make a wrong guess here hard to spot:

1. `LinksTo` on a bad path returns nil rather than erroring, so every entry
   simply looks like a broken reference.
2. `GetElementNativeValues(entry, 'LVLO\Level')` works anyway, because xEdit
   prefix-matches `LVLO` against `LVLO - Base Data`. Level and Count read
   correctly while the reference silently fails.

The result is a report full of confident, wrong `NULLREF` findings. During
development that pattern was misdiagnosed twice — once as stale element
handles, once as a field naming difference — before a diagnostic run showed
what was actually there.

If you fork this for another game, or a future xEdit changes the layout, run
the diagnostic before assuming anything.

---

## LLDiag.pas

Dumps the full element tree of leveled list entries, then tests nine candidate
paths for the reference field and six for level and count, showing which
resolve and which return nil.

**Usage**

1. Place in `<xEdit folder>\Edit Scripts\`
2. Select any plugin containing leveled lists
3. Right-click → Apply Script → **LLDiag**
4. Read `Edit Scripts\LLDiag.txt`

Samples three LVLI and three LVLN lists by default. Change `iMaxSamples` at the
top if you want more.

**Sample output**

```
--- FULL TREE OF ENTRY [0] ---
- Name="Leveled List Entry"  Sig="LVLO"  Value=""
  path: Leveled List Entry
  - Name="LVLO - Base Data"  Sig="LVLO"  Value=""
    path: Leveled List Entry\LVLO - Base Data
    - Name="Level"  Sig=""  Value="1"
    - Name="Item"  Sig=""  Value="SomeWeapon [WEAP:0001F66B]"
    - Name="Count"  Sig=""  Value="1"
    - Name="Chance None"  Sig=""  Value="0"

--- ACCESS TESTS (reference field) ---
  LVLO - Base Data\Item          -> SomeWeapon  <WEAP>
  LVLO - Base Data\NPC           -> nil
  LVLO\Item                      -> nil
  ...
```

Whichever line resolves is the path to use.

---

## Adding your own

The pattern is short enough to copy. `Process` filters to the records you care
about, a dump procedure prints the tree, and `Finalize` writes the file. Keep
them read-only — a diagnostic that modifies plugins is a trap.

---

## License

MIT, same as the rest of the repository. See [../../LICENSE](../../LICENSE).
