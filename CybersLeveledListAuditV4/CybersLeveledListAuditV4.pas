{
  Cyber's Leveled List Auditor v4
  Author  : CyberDanz
  License : MIT - free to use, modify, fork and redistribute.
            Keep this notice with the code.

  Structured diagnostic logging plus override-chain injection cross-check.
  Outputs: LeveledListAudit.txt (human), LeveledListAudit.csv (sortable)

  Install : place in <xEdit folder>\Edit Scripts\
  Usage   : select plugin(s) or the LVLI/LVLN top-level group,
            right-click > Apply Script > LeveledListAudit
  Optional: Edit Scripts\lltiers.txt for manual tier overrides
              ITEM  <FormID or EditorID>  <tier 0-10>
              LIST  <FormID or EditorID>  <minTier>  <maxTier>

  v4 changes
    - Process() anchors on MasterOrSelf so every pass agrees on which record
      it is talking about; WalkList evaluates the winning override.
    - New InjectionCheck pass walks the override chain per list and emits:
        INJECT      informational, plugin added entries
        CLOBBER     critical, plugin dropped entries the previous state had
        LOSTINJECT  critical, injected entries missing from the winner
    - Entry identity keys on target|level|count so two mods adding the same
      item at different levels are not collapsed together.
}
unit LeveledListAudit;

var
  slReport      : TStringList;
  slCsv         : TStringList;
  slListIndex   : TStringList;
  slRefCount    : TStringList;
  slInjections  : TStringList;
  slTiers       : TStringList;
  slTierCache   : TStringList;
  slVisiting    : TStringList;
  slCounts      : TStringList;   // tag -> occurrence count
  slNameCache   : TStringList;   // FormID hex -> EditorID, for report labels
  iMaxDepth     : Integer;
  bHaveTiers    : Boolean;
  fWeapDmgMax   : Real;
  fArmoRatMax   : Real;
  iFindingNo    : Integer;

//-------------------------------------------------------------------
function Initialize: Integer;
var
  sPath: string;
begin
  slReport     := TStringList.Create;
  slCsv        := TStringList.Create;
  slListIndex  := TStringList.Create;
  slRefCount   := TStringList.Create;
  slInjections := TStringList.Create;
  slTiers      := TStringList.Create;
  slTierCache  := TStringList.Create;
  slVisiting   := TStringList.Create;
  slCounts     := TStringList.Create;
  slNameCache  := TStringList.Create;

  slNameCache.Sorted     := True;
  slNameCache.Duplicates := dupIgnore;
  slNameCache.NameValueSeparator := '=';

  slListIndex.Sorted  := True;
  slRefCount.Sorted   := True;
  slInjections.Sorted := True;
  slTierCache.Sorted  := True;
  slCounts.Sorted     := True;

  iMaxDepth   := 0;
  iFindingNo  := 0;
  fWeapDmgMax := 100.0;
  fArmoRatMax := 50.0;

  sPath := ScriptsPath + 'lltiers.txt';
  bHaveTiers := FileExists(sPath);
  if bHaveTiers then
    slTiers.LoadFromFile(sPath);

  slCsv.Add('ID,Severity,Tag,OriginPlugin,WinningPlugin,ListEditorID,ListFormID,' +
            'EntryIndex,TargetEditorID,TargetFormID,TargetSig,Level,Count,' +
            'Depth,Path,Detail,SuggestedFix');
  Result := 0;
end;

//-------------------------------------------------------------------
function KeyOf(e: IInterface): string;
begin
  if not Assigned(e) then begin
    Result := '00000000';
    Exit;
  end;
  Result := IntToHex(FixedFormID(e), 8);
end;

function SafeName(e: IInterface): string;
begin
  if not Assigned(e) then begin
    Result := '<NULL>';
    Exit;
  end;
  Result := EditorID(e);
  if Result = '' then
    Result := Name(e);
  Result := Result + ' [' + IntToHex(FixedFormID(e), 8) + ']';
end;

function IsLeveled(e: IInterface): Boolean;
var
  s: string;
begin
  Result := False;
  if not Assigned(e) then Exit;
  s := Signature(e);
  Result := (s = 'LVLI') or (s = 'LVLN');
end;

function Clamp(v, lo, hi: Integer): Integer;
begin
  Result := v;
  if Result < lo then Result := lo;
  if Result > hi then Result := hi;
end;

function CsvSafe(s: string): string;
begin
  Result := StringReplace(s, '"', '''', [rfReplaceAll]);
  Result := StringReplace(Result, ',', ';', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function PluginOf(e: IInterface): string;
begin
  Result := '<unknown>';
  if not Assigned(e) then Exit;
  Result := GetFileName(GetFile(e));
end;

//-------------------------------------------------------------------
// Provenance: which plugin defines this record, and which one wins
function OriginPlugin(e: IInterface): string;
var
  m: IInterface;
begin
  Result := '<unknown>';
  if not Assigned(e) then Exit;
  m := MasterOrSelf(e);
  if Assigned(m) then
    Result := GetFileName(GetFile(m));
end;

function WinningPlugin(e: IInterface): string;
var
  w: IInterface;
begin
  Result := '<unknown>';
  if not Assigned(e) then Exit;
  w := WinningOverride(e);
  if Assigned(w) then
    Result := GetFileName(GetFile(w));
end;

function OverrideChain(e: IInterface): string;
var
  i: Integer;
  m, ovr: IInterface;
begin
  Result := '';
  if not Assigned(e) then Exit;
  m := MasterOrSelf(e);
  if not Assigned(m) then Exit;
  Result := GetFileName(GetFile(m));
  for i := 0 to Pred(OverrideCount(m)) do begin
    ovr := OverrideByIndex(m, i);
    if Assigned(ovr) then
      Result := Result + ' -> ' + GetFileName(GetFile(ovr));
  end;
end;

//-------------------------------------------------------------------
// Central logger. Every finding routes through here.
procedure Log(sev, tag: string; lst, ref: IInterface;
              entryIdx, lvl, cnt, depth: Integer;
              path, detail, fix: string);
var
  idx: Integer;
  sLine, sSig: string;
begin
  Inc(iFindingNo);

  idx := slCounts.IndexOf(tag);
  if idx < 0 then
    slCounts.AddObject(tag, TObject(1))
  else
    slCounts.Objects[idx] := TObject(Integer(slCounts.Objects[idx]) + 1);

  sSig := '';
  if Assigned(ref) then
    sSig := Signature(ref);

  // --- human-readable block ---
  slReport.Add('');
  slReport.Add('#' + IntToStr(iFindingNo) + '  [' + sev + '] ' + tag);
  slReport.Add('  List      : ' + SafeName(lst));
  slReport.Add('  Origin    : ' + OriginPlugin(lst));
  slReport.Add('  Winner    : ' + WinningPlugin(lst));
  slReport.Add('  Chain     : ' + OverrideChain(lst));
  if entryIdx >= 0 then
    slReport.Add('  Entry     : index ' + IntToStr(entryIdx) +
                 '   (xEdit path: Leveled List Entries\[' + IntToStr(entryIdx) + ']\LVLO)');
  if Assigned(ref) then begin
    slReport.Add('  Target    : ' + SafeName(ref) + '  <' + sSig + '>');
    slReport.Add('  TgtOrigin : ' + OriginPlugin(ref));
  end;
  if lvl >= 0 then
    slReport.Add('  Level     : ' + IntToStr(lvl));
  if cnt >= 0 then
    slReport.Add('  Count     : ' + IntToStr(cnt));
  slReport.Add('  Depth     : ' + IntToStr(depth));
  slReport.Add('  Path      : ' + path);
  slReport.Add('  Detail    : ' + detail);
  slReport.Add('  Fix       : ' + fix);

  // --- csv row ---
  sLine :=
    IntToStr(iFindingNo) + ',' + sev + ',' + tag + ',' +
    CsvSafe(OriginPlugin(lst)) + ',' + CsvSafe(WinningPlugin(lst)) + ',' +
    CsvSafe(EditorID(lst)) + ',' + KeyOf(lst) + ',' +
    IntToStr(entryIdx) + ',';
  if Assigned(ref) then
    sLine := sLine + CsvSafe(EditorID(ref)) + ',' + KeyOf(ref) + ',' + sSig + ','
  else
    sLine := sLine + ',,,';
  sLine := sLine + IntToStr(lvl) + ',' + IntToStr(cnt) + ',' + IntToStr(depth) + ',' +
           CsvSafe(path) + ',' + CsvSafe(detail) + ',' + CsvSafe(fix);
  slCsv.Add(sLine);
end;

//-------------------------------------------------------------------
function TierOverride(e: IInterface): Integer;
var
  i: Integer;
  sl: TStringList;
  sID, sEd: string;
begin
  Result := -1;
  if not bHaveTiers then Exit;
  if not Assigned(e) then Exit;
  sID := Uppercase(IntToHex(FixedFormID(e), 8));
  sEd := Uppercase(EditorID(e));
  sl := TStringList.Create;
  try
    sl.Delimiter := ' ';
    for i := 0 to Pred(slTiers.Count) do begin
      sl.DelimitedText := slTiers[i];
      if sl.Count < 3 then Continue;
      if Uppercase(sl[0]) <> 'ITEM' then Continue;
      if (Uppercase(sl[1]) = sEd) or (Uppercase(sl[1]) = sID) then begin
        Result := StrToIntDef(sl[2], -1);
        Exit;
      end;
    end;
  finally
    sl.Free;
  end;
end;

procedure TierBandOfList(e: IInterface; var lo, hi: Integer);
var
  i: Integer;
  sl: TStringList;
  sID, sEd: string;
begin
  lo := -1;
  hi := -1;
  if not bHaveTiers then Exit;
  if not Assigned(e) then Exit;
  sID := Uppercase(IntToHex(FixedFormID(e), 8));
  sEd := Uppercase(EditorID(e));
  sl := TStringList.Create;
  try
    sl.Delimiter := ' ';
    for i := 0 to Pred(slTiers.Count) do begin
      sl.DelimitedText := slTiers[i];
      if sl.Count < 4 then Continue;
      if Uppercase(sl[0]) <> 'LIST' then Continue;
      if (Uppercase(sl[1]) = sEd) or (Uppercase(sl[1]) = sID) then begin
        lo := StrToIntDef(sl[2], -1);
        hi := StrToIntDef(sl[3], -1);
        Exit;
      end;
    end;
  finally
    sl.Free;
  end;
end;

function AmmoWeight(w: IInterface): Real;
var
  ammo: IInterface;
  s: string;
begin
  Result := 1.0;
  ammo := LinksTo(ElementByPath(w, 'DNAM\Ammo'));
  if not Assigned(ammo) then Exit;
  s := Uppercase(EditorID(ammo));
  if Pos('MININUKE', s) > 0 then Result := 2.0
  else if Pos('MISSILE', s) > 0 then Result := 1.8
  else if Pos('FUSIONCORE', s) > 0 then Result := 1.6
  else if Pos('50', s) > 0 then Result := 1.4
  else if Pos('PLASMA', s) > 0 then Result := 1.35
  else if Pos('SHELL', s) > 0 then Result := 1.3
  else if Pos('308', s) > 0 then Result := 1.3
  else if Pos('44', s) > 0 then Result := 1.25
  else if Pos('CELL', s) > 0 then Result := 1.2
  else if Pos('5MM', s) > 0 then Result := 1.15
  else if Pos('45', s) > 0 then Result := 1.1
  else if Pos('10MM', s) > 0 then Result := 1.0
  else if Pos('38', s) > 0 then Result := 0.85
  else if Pos('SYRINGE', s) > 0 then Result := 0.5;
end;

function DeriveTier(e: IInterface): Integer;
var
  sig: string;
  dmg, rate, value, rating, score: Real;
begin
  Result := -1;
  if not Assigned(e) then Exit;
  sig := Signature(e);

  if sig = 'WEAP' then begin
    dmg   := GetElementNativeValues(e, 'DNAM\Attack Damage');
    rate  := GetElementNativeValues(e, 'DNAM\Attack Delay Sec');
    value := GetElementNativeValues(e, 'DATA\Value');
    if dmg > fWeapDmgMax then fWeapDmgMax := dmg;
    if rate > 0.01 then score := dmg / rate else score := dmg * 4.0;
    score := score * AmmoWeight(e);
    if value > 0 then score := (score * 0.8) + (value * 0.2);
    if fWeapDmgMax > 0 then
      Result := Clamp(Round((score / (fWeapDmgMax * 4.0)) * 10.0), 0, 10)
    else
      Result := 0;
    Exit;
  end;

  if sig = 'ARMO' then begin
    rating := GetElementNativeValues(e, 'DNAM - Armor Rating');
    if rating = 0 then
      rating := GetElementNativeValues(e, 'DATA\Armor Rating');
    value := GetElementNativeValues(e, 'DATA\Value');
    if rating > fArmoRatMax then fArmoRatMax := rating;
    score := (rating * 0.75) + (value * 0.05);
    if fArmoRatMax > 0 then
      Result := Clamp(Round((score / fArmoRatMax) * 10.0), 0, 10)
    else
      Result := 0;
    Exit;
  end;

  if (sig = 'ALCH') or (sig = 'AMMO') or (sig = 'MISC') then begin
    value := GetElementNativeValues(e, 'DATA\Value');
    if value <= 0 then
      value := GetElementNativeValues(e, 'DATA - Value');
    Result := Clamp(Round(value / 30.0), 0, 10);
  end;
end;

function TierOfItem(e: IInterface): Integer;
var
  idx, t: Integer;
  key: string;
begin
  Result := -1;
  if not Assigned(e) then Exit;
  t := TierOverride(e);
  if t >= 0 then begin
    Result := t;
    Exit;
  end;
  key := KeyOf(e);
  idx := slTierCache.IndexOf(key);
  if idx >= 0 then begin
    Result := Integer(slTierCache.Objects[idx]);
    Exit;
  end;
  t := DeriveTier(e);
  slTierCache.AddObject(key, TObject(t));
  Result := t;
end;

function TierSource(e: IInterface): string;
begin
  if TierOverride(e) >= 0 then
    Result := 'manual'
  else
    Result := 'auto-derived';
end;

//-------------------------------------------------------------------
// Shared entry accessor: resolves the LVLO target for one entry element.
function EntryTarget(entry: IInterface): IInterface;
begin
  Result := LinksTo(ElementBySignature(entry, 'LVLO'));
  if not Assigned(Result) then
    Result := LinksTo(ElementByPath(entry, 'LVLO\Reference'));
end;

//-------------------------------------------------------------------
// Anchor on the master record so every pass agrees on identity.
function Process(e: IInterface): Integer;
var
  m: IInterface;
  key: string;
begin
  Result := 0;
  if not IsLeveled(e) then Exit;
  m := MasterOrSelf(e);
  if not Assigned(m) then m := e;
  key := KeyOf(m);
  if slListIndex.IndexOf(key) < 0 then
    slListIndex.AddObject(key, TObject(m));
end;

//-------------------------------------------------------------------
procedure WalkList(e: IInterface; depth: Integer; accChance: Real; path: string);
var
  entries, entry, ref, cur: IInterface;
  i, lvl, cnt, tier, tlo, thi, idx: Integer;
  cn: Real;
  key, ipath, injKey, sEid: string;
  effChance: Real;
begin
  if not Assigned(e) then Exit;

  // Always evaluate the record the game will actually use.
  cur := WinningOverride(e);
  if not Assigned(cur) then cur := e;

  key := KeyOf(cur);

  if slVisiting.IndexOf(key) >= 0 then begin
    Log('CRITICAL', 'CYCLE', cur, nil, -1, -1, -1, depth, path,
        'Circular nesting: this list is reachable from itself. Game may hang or ' +
        'fail to resolve the list at runtime.',
        'Open ' + EditorID(cur) + ' and remove the nested entry that closes the loop. ' +
        'Trace the Path field above to find it.');
    Exit;
  end;
  slVisiting.Add(key);

  if depth > iMaxDepth then iMaxDepth := depth;

  if depth > 12 then begin
    Log('WARN', 'DEPTH', cur, nil, -1, -1, -1, depth, path,
        'Nesting depth ' + IntToStr(depth) + ' exceeds practical limits.',
        'Flatten intermediate lists, or verify a patch has not chained lists unintentionally.');
    idx := slVisiting.IndexOf(key);
    if idx >= 0 then slVisiting.Delete(idx);
    Exit;
  end;

  sEid := EditorID(cur);
  if sEid = '' then sEid := key;
  if path = '' then ipath := sEid else ipath := path + ' > ' + sEid;

  cn := GetElementNativeValues(cur, 'LVLD - Chance None');
  effChance := accChance * (1.0 - (cn / 100.0));

  if (effChance < 0.05) and (effChance > 0) then
    Log('WARN', 'CHANCE', cur, nil, -1, -1, -1, depth, ipath,
        'Cumulative Chance None across the nesting path leaves an effective spawn ' +
        'rate of ' + FloatToStr(effChance * 100) + '%. Items here will almost never appear.',
        'Reduce LVLD - Chance None on this list or a parent. Check each list in the ' +
        'Path field; the multiplier compounds at every level.');

  TierBandOfList(cur, tlo, thi);

  entries := ElementByName(cur, 'Leveled List Entries');
  if not Assigned(entries) then begin
    Log('WARN', 'EMPTY', cur, nil, -1, -1, -1, depth, ipath,
        'List has no entries. Anything rolling on it gets nothing.',
        'If a patch emptied this list, check the Chain field for which plugin ' +
        'overrode it and restore entries in your patch.');
    idx := slVisiting.IndexOf(key);
    if idx >= 0 then slVisiting.Delete(idx);
    Exit;
  end;

  for i := 0 to Pred(ElementCount(entries)) do begin
    entry := ElementByIndex(entries, i);
    ref   := EntryTarget(entry);
    lvl   := GetElementNativeValues(entry, 'LVLO\Level');
    cnt   := GetElementNativeValues(entry, 'LVLO\Count');

    if not Assigned(ref) then begin
      Log('CRITICAL', 'NULLREF', cur, nil, i, lvl, cnt, depth, ipath,
          'Entry reference resolves to nothing - the target record is missing or ' +
          'the plugin that defined it is not loaded.',
          'Open the list, go to entry index ' + IntToStr(i) + ', and either delete ' +
          'the row or repoint it. Check the Origin plugin for a missing master.');
      Continue;
    end;

    idx := slRefCount.IndexOf(KeyOf(ref));
    if idx < 0 then
      slRefCount.AddObject(KeyOf(ref), TObject(1))
    else
      slRefCount.Objects[idx] := TObject(Integer(slRefCount.Objects[idx]) + 1);

    injKey := key + '|' + KeyOf(ref);
    if slInjections.IndexOf(injKey) >= 0 then
      Log('WARN', 'DUPE', cur, ref, i, lvl, cnt, depth, ipath,
          'This target appears more than once in the same list, doubling its roll weight.',
          'Likely two mods injected the same item. Compare the Chain field across ' +
          'both entries and remove the redundant one in your patch.')
    else
      slInjections.Add(injKey);

    if lvl <= 0 then
      Log('WARN', 'LEVEL', cur, ref, i, lvl, cnt, depth, ipath,
          'Entry level is ' + IntToStr(lvl) + '. Level 0 entries are always available ' +
          'regardless of player level.',
          'Set LVLO\Level to the intended minimum player level, or confirm this is deliberate.');

    if lvl > 100 then
      Log('INFO', 'LEVEL', cur, ref, i, lvl, cnt, depth, ipath,
          'Entry level ' + IntToStr(lvl) + ' is above realistic play range - effectively unreachable.',
          'Lower LVLO\Level, or accept this entry will never roll.');

    if cnt <= 0 then
      Log('CRITICAL', 'COUNT', cur, ref, i, lvl, cnt, depth, ipath,
          'Entry count is ' + IntToStr(cnt) + '. Zero-count entries produce nothing when rolled.',
          'Set LVLO\Count to 1 or higher at entry index ' + IntToStr(i) + '.');

    if cnt > 20 then
      Log('INFO', 'COUNT', cur, ref, i, lvl, cnt, depth, ipath,
          'Entry count ' + IntToStr(cnt) + ' is unusually high for a single roll.',
          'Verify this is intended - high counts on weapons/armor are usually a typo.');

    if tlo >= 0 then begin
      tier := TierOfItem(ref);
      if (tier >= 0) and (tier < tlo) then
        Log('INFO', 'BALANCE', cur, ref, i, lvl, cnt, depth, ipath,
            'Target tier ' + IntToStr(tier) + ' (' + TierSource(ref) + ') is below the ' +
            'list band ' + IntToStr(tlo) + '-' + IntToStr(thi) + ' - underpowered for this list.',
            'Move to a lower-tier list, or widen the band in lltiers.txt if the ' +
            'auto-derived tier is wrong.');
      if (tier >= 0) and (thi >= 0) and (tier > thi) then
        Log('WARN', 'BALANCE', cur, ref, i, lvl, cnt, depth, ipath,
            'Target tier ' + IntToStr(tier) + ' (' + TierSource(ref) + ') exceeds the ' +
            'list band ' + IntToStr(tlo) + '-' + IntToStr(thi) + ' - grants early access to late-game gear.',
            'Raise LVLO\Level on this entry, move it to a higher-tier list, or ' +
            'correct the tier in lltiers.txt if auto-derivation misjudged it.');
    end;

    if IsLeveled(ref) then
      WalkList(ref, depth + 1, effChance, ipath);
  end;

  idx := slVisiting.IndexOf(key);
  if idx >= 0 then slVisiting.Delete(idx);
end;

//-------------------------------------------------------------------
procedure SpreadCheck(e: IInterface);
var
  entries, entry, ref, refLo, refHi, cur: IInterface;
  i, t, tmin, tmax, seen: Integer;
begin
  if not Assigned(e) then Exit;
  cur := WinningOverride(e);
  if not Assigned(cur) then cur := e;

  entries := ElementByName(cur, 'Leveled List Entries');
  if not Assigned(entries) then Exit;

  tmin := 99;
  tmax := -1;
  seen := 0;
  refLo := nil;
  refHi := nil;

  for i := 0 to Pred(ElementCount(entries)) do begin
    entry := ElementByIndex(entries, i);
    ref := EntryTarget(entry);
    if not Assigned(ref) then Continue;
    if IsLeveled(ref) then Continue;
    t := TierOfItem(ref);
    if t < 0 then Continue;
    Inc(seen);
    if t < tmin then begin tmin := t; refLo := ref; end;
    if t > tmax then begin tmax := t; refHi := ref; end;
  end;

  if (seen >= 3) and ((tmax - tmin) >= 6) then
    Log('WARN', 'SPREAD', cur, refHi, -1, -1, -1, 0, EditorID(cur),
        'Entry tiers span ' + IntToStr(tmin) + '-' + IntToStr(tmax) + ' in one list. ' +
        'Weakest: ' + SafeName(refLo) + ' (tier ' + IntToStr(tmin) + '). ' +
        'Strongest: ' + SafeName(refHi) + ' (tier ' + IntToStr(tmax) + '). ' +
        'Two rolls on this list produce wildly different power outcomes.',
        'Split into tiered sub-lists, or gate the high-tier entries behind a ' +
        'higher LVLO\Level.');
end;

//-------------------------------------------------------------------
//  INJECTION CROSS-CHECK
//-------------------------------------------------------------------
// Entry identity includes level and count so that two plugins adding the
// same item at different levels are not treated as the same entry.
function EntryKey(entry: IInterface): string;
var
  ref: IInterface;
  lvl, cnt: Integer;
begin
  Result := '';
  ref := EntryTarget(entry);
  if not Assigned(ref) then Exit;
  lvl := GetElementNativeValues(entry, 'LVLO\Level');
  cnt := GetElementNativeValues(entry, 'LVLO\Count');
  Result := KeyOf(ref) + '|L' + IntToStr(lvl) + '|C' + IntToStr(cnt);
end;

// Human-readable label for a stored entry key. Names come from slNameCache,
// which is populated by EntrySetOf as it resolves each entry - this avoids
// a global FormID lookup that would miss records defined in mod plugins.
function DescribeKey(sKey: string): string;
var
  p, idx: Integer;
  sForm, sRest, sEid: string;
begin
  Result := sKey;
  p := Pos('|', sKey);
  if p <= 0 then Exit;
  sForm := Copy(sKey, 1, p - 1);
  sRest := Copy(sKey, p + 1, Length(sKey));
  sEid := '';
  idx := slNameCache.IndexOfName(sForm);
  if idx >= 0 then
    sEid := slNameCache.ValueFromIndex[idx];
  if sEid <> '' then
    Result := sEid + ' [' + sForm + '] (' + sRest + ')'
  else
    Result := '[' + sForm + '] (' + sRest + ')';
end;

function EntrySetOf(lst: IInterface): TStringList;
var
  entries, entry, ref: IInterface;
  i: Integer;
  sKey, sForm, sEid: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  if not Assigned(lst) then Exit;
  entries := ElementByName(lst, 'Leveled List Entries');
  if not Assigned(entries) then Exit;
  for i := 0 to Pred(ElementCount(entries)) do begin
    entry := ElementByIndex(entries, i);
    sKey := EntryKey(entry);
    if sKey = '' then Continue;
    Result.Add(sKey);

    // remember a readable name for this target while we still have the record
    ref := EntryTarget(entry);
    if Assigned(ref) then begin
      sForm := KeyOf(ref);
      if slNameCache.IndexOfName(sForm) < 0 then begin
        sEid := EditorID(ref);
        if sEid = '' then sEid := Name(ref);
        sEid := StringReplace(sEid, '=', '-', [rfReplaceAll]);
        if sEid <> '' then
          slNameCache.Add(sForm + '=' + sEid);
      end;
    end;
  end;
end;

// Returns members of a that are absent from b, as a display string.
function DiffKeys(a, b: TStringList; iLimit: Integer): string;
var
  i, n: Integer;
begin
  Result := '';
  n := 0;
  for i := 0 to Pred(a.Count) do begin
    if b.IndexOf(a[i]) < 0 then begin
      Inc(n);
      if n <= iLimit then begin
        if Result <> '' then Result := Result + '; ';
        Result := Result + DescribeKey(a[i]);
      end;
    end;
  end;
  if n > iLimit then
    Result := Result + '; (+' + IntToStr(n - iLimit) + ' more)';
end;

procedure InjectionCheck(m: IInterface);
var
  i, oc: Integer;
  ovr, win: IInterface;
  slPrev, slCur, slWin, slBase: TStringList;
  sAdded, sLost, sOrphan, sPlugin, sWinPlugin: string;
begin
  if not Assigned(m) then Exit;

  oc := OverrideCount(m);
  if oc = 0 then Exit;              // single definition, nothing to reconcile

  win := WinningOverride(m);
  if not Assigned(win) then win := m;
  sWinPlugin := PluginOf(win);

  slBase := EntrySetOf(m);          // original definition, kept for reference
  slWin  := EntrySetOf(win);
  slPrev := TStringList.Create;
  slPrev.Sorted := True;
  slPrev.Duplicates := dupIgnore;
  slPrev.Assign(slBase);

  try
    for i := 0 to Pred(oc) do begin
      ovr := OverrideByIndex(m, i);
      if not Assigned(ovr) then Continue;
      sPlugin := PluginOf(ovr);
      slCur := EntrySetOf(ovr);
      try
        // Entries this plugin added relative to the state before it.
        sAdded := DiffKeys(slCur, slPrev, 8);

        // Entries present before this plugin that it no longer carries.
        sLost := DiffKeys(slPrev, slCur, 8);

        if sLost <> '' then
          Log('CRITICAL', 'CLOBBER', ovr, nil, -1, -1, -1, 0, sPlugin,
              sPlugin + ' drops entries that were present in the record before it ' +
              'in the load order: ' + sLost + '. This wipes content the base game or ' +
              'an earlier mod expects. Note: a deliberate removal patch will also ' +
              'trigger this.',
              'If unintended, rebuild the list in a patch carrying the union of all ' +
              'entries from every plugin in the Chain field.');

        if sAdded <> '' then
          Log('INFO', 'INJECT', ovr, nil, -1, -1, -1, 0, sPlugin,
              sPlugin + ' adds entries: ' + sAdded,
              'No action needed unless these are absent from the winning override - ' +
              'see any LOSTINJECT finding for this list.');

        // The load-order-critical case: entries a losing plugin injected that
        // the winning record does not carry.
        if not SameText(sPlugin, sWinPlugin) then begin
          sOrphan := '';
          if slCur.Count > 0 then
            sOrphan := DiffKeys(slCur, slWin, 8);
          if sOrphan <> '' then
            Log('CRITICAL', 'LOSTINJECT', ovr, nil, -1, -1, -1, 0, sPlugin,
                'Entries carried by ' + sPlugin + ' are absent from the winning ' +
                'override (' + sWinPlugin + '): ' + sOrphan + '. These will not ' +
                'appear in game.',
                'Create a patch loaded after both plugins containing the entries ' +
                'from each, or add ' + sPlugin + ' to your Bashed Patch / Smashed ' +
                'Patch merge sources.');
        end;

        slPrev.Assign(slCur);   // walk forward through the chain
      finally
        slCur.Free;
      end;
    end;
  finally
    slPrev.Free;
    slWin.Free;
    slBase.Free;
  end;
end;

//-------------------------------------------------------------------
function Finalize: Integer;
var
  i: Integer;
  e: IInterface;
  sOut, sCsvOut: string;
begin
  AddMessage('Indexed ' + IntToStr(slListIndex.Count) + ' leveled lists.');

  slReport.Add('=== Cyber''s Leveled List Auditor v4 (by CyberDanz) ===');
  slReport.Add('Generated: ' + DateToStr(Now) + ' ' + TimeToStr(Now));
  slReport.Add('Tier overrides: ' + BoolToStr(bHaveTiers, True));
  slReport.Add('');
  slReport.Add('SEVERITY KEY');
  slReport.Add('  CRITICAL - will break at runtime or silently lose content; fix before playing');
  slReport.Add('  WARN     - behaves unexpectedly; probably not what you intended');
  slReport.Add('  INFO     - worth a look; may be deliberate');
  slReport.Add('');
  slReport.Add('TAG KEY');
  slReport.Add('  CYCLE      - list reachable from itself');
  slReport.Add('  NULLREF    - entry points at a missing record');
  slReport.Add('  COUNT      - zero or implausible entry count');
  slReport.Add('  LEVEL      - zero or unreachable entry level');
  slReport.Add('  CHANCE     - compounded Chance None makes the list near-dead');
  slReport.Add('  DEPTH      - excessive nesting');
  slReport.Add('  EMPTY      - list has no entries');
  slReport.Add('  DUPE       - same target twice in one list');
  slReport.Add('  SPREAD     - very wide power range within one list');
  slReport.Add('  BALANCE    - entry tier outside the configured band');
  slReport.Add('  ORPHAN     - no other leveled list references this one');
  slReport.Add('  INJECT     - a plugin added entries to this list');
  slReport.Add('  CLOBBER    - a plugin dropped entries an earlier plugin had');
  slReport.Add('  LOSTINJECT - injected entries missing from the winning override');
  slReport.Add('');
  slReport.Add('=== FINDINGS ===');

  // Pass 1: structural walk of the winning version of each list.
  for i := 0 to Pred(slListIndex.Count) do begin
    e := ObjectToElement(slListIndex.Objects[i]);
    slVisiting.Clear;
    WalkList(e, 0, 1.0, '');
  end;

  // Pass 2: power spread within a single list.
  for i := 0 to Pred(slListIndex.Count) do
    SpreadCheck(ObjectToElement(slListIndex.Objects[i]));

  // Pass 3: override-chain injection cross-check.
  for i := 0 to Pred(slListIndex.Count) do
    InjectionCheck(ObjectToElement(slListIndex.Objects[i]));

  // Pass 4: lists nothing else points at.
  for i := 0 to Pred(slListIndex.Count) do begin
    e := ObjectToElement(slListIndex.Objects[i]);
    if slRefCount.IndexOf(KeyOf(e)) < 0 then
      Log('INFO', 'ORPHAN', e, nil, -1, -1, -1, 0, EditorID(e),
          'No other leveled list references this one. Note: containers, NPC ' +
          'inventories and quest scripts are NOT scanned, so this may be a false positive.',
          'Search the FormID in xEdit (Ctrl+F) to confirm nothing references it ' +
          'before deleting.');
  end;

  slReport.Add('');
  slReport.Add('=== SUMMARY ===');
  slReport.Add('Total findings   : ' + IntToStr(iFindingNo));
  for i := 0 to Pred(slCounts.Count) do
    slReport.Add('  ' + slCounts[i] + ' : ' + IntToStr(Integer(slCounts.Objects[i])));
  slReport.Add('Lists indexed    : ' + IntToStr(slListIndex.Count));
  slReport.Add('Items auto-tiered: ' + IntToStr(slTierCache.Count));
  slReport.Add('Max nesting depth: ' + IntToStr(iMaxDepth));

  sOut    := ScriptsPath + 'LeveledListAudit.txt';
  sCsvOut := ScriptsPath + 'LeveledListAudit.csv';
  slReport.SaveToFile(sOut);
  slCsv.SaveToFile(sCsvOut);

  AddMessage('Report  : ' + sOut);
  AddMessage('CSV     : ' + sCsvOut);
  AddMessage('Findings: ' + IntToStr(iFindingNo));

  slReport.Free;
  slCsv.Free;
  slListIndex.Free;
  slRefCount.Free;
  slInjections.Free;
  slTiers.Free;
  slTierCache.Free;
  slVisiting.Free;
  slCounts.Free;
  slNameCache.Free;
  Result := 0;
end;

end.
