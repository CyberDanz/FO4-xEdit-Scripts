{
  LLDiag - Leveled List Structure Diagnostic
  Part of Cyber's Leveled List Auditor
  https://github.com/CyberDanz/FO4-xEdit-Scripts

  Dumps the element tree of leveled list entries so you can see the real
  field names and paths your xEdit build uses, instead of assuming them.

  Why this exists
  ---------------
  Leveled list entry layout is not stable across games or xEdit versions.
  In FO4 with xEdit 4.1.5q the reference field sits at:

      Leveled List Entry \ LVLO - Base Data \ Item     (LVLI)
      Leveled List Entry \ LVLO - Base Data \ NPC      (LVLN)

  Assuming a different path costs you silently: LinksTo returns nil and
  every entry looks like a broken reference. Worse, 'LVLO\Level' still
  resolves because xEdit prefix-matches 'LVLO' against 'LVLO - Base Data',
  so Level and Count read correctly while the reference never does. That
  partial success is easy to misread as a different bug entirely.

  Run this first whenever entry resolution looks wrong.

  Install : place in <xEdit folder>\Edit Scripts\
  Usage   : select any plugin containing leveled lists, right-click,
            Apply Script > LLDiag
  Output  : Edit Scripts\LLDiag.txt

  Read-only. Modifies nothing.

  Configuration: iMaxSamples below controls how many lists of each type
  are dumped. Three is usually plenty.
}
unit LLDiag;

const
  iMaxSamples = 3;

var
  slOut     : TStringList;
  iDoneLVLI : Integer;
  iDoneLVLN : Integer;

function Initialize: Integer;
begin
  slOut := TStringList.Create;
  iDoneLVLI := 0;
  iDoneLVLN := 0;
  slOut.Add('=== Leveled List Structure Diagnostic ===');
  slOut.Add('');
  slOut.Add('Samples up to ' + IntToStr(iMaxSamples) + ' LVLI and ' +
            IntToStr(iMaxSamples) + ' LVLN lists.');
  slOut.Add('The ACCESS TESTS section shows which paths resolve and which');
  slOut.Add('return nil. Use whichever resolves in your own scripts.');
  slOut.Add('');
  Result := 0;
end;

procedure DumpElement(e: IInterface; depth: Integer; prefix: string);
var
  i: Integer;
  child: IInterface;
  sPad, sVal, sPath: string;
begin
  if not Assigned(e) then Exit;
  if depth > 4 then Exit;

  sPad := '';
  for i := 1 to depth do sPad := sPad + '  ';

  sVal := GetEditValue(e);
  if Length(sVal) > 70 then sVal := Copy(sVal, 1, 70) + '...';

  sPath := prefix;
  if sPath <> '' then sPath := sPath + '\';
  sPath := sPath + Name(e);

  slOut.Add(sPad + '- Name="' + Name(e) + '"' +
            '  Sig="' + Signature(e) + '"' +
            '  Value="' + sVal + '"');
  slOut.Add(sPad + '  path: ' + sPath);

  for i := 0 to ElementCount(e) - 1 do begin
    child := ElementByIndex(e, i);
    DumpElement(child, depth + 1, sPath);
  end;
end;

// Try one path and report whether it resolved.
procedure TestPath(entry: IInterface; sPath: string);
var
  ref: IInterface;
  sPad: string;
begin
  sPad := sPath;
  while Length(sPad) < 30 do sPad := sPad + ' ';
  ref := LinksTo(ElementByPath(entry, sPath));
  if Assigned(ref) then
    slOut.Add('  ' + sPad + ' -> ' + EditorID(ref) + '  <' + Signature(ref) + '>')
  else
    slOut.Add('  ' + sPad + ' -> nil');
end;

procedure DumpList(e: IInterface);
var
  entries, entry: IInterface;
begin
  entries := ElementByName(e, 'Leveled List Entries');
  if not Assigned(entries) then Exit;
  if ElementCount(entries) = 0 then Exit;

  slOut.Add('###############################################');
  slOut.Add(Signature(e) + ' LIST : ' + EditorID(e) +
            ' [' + IntToHex(FixedFormID(e), 8) + ']');
  slOut.Add('Plugin      : ' + GetFileName(GetFile(e)));
  slOut.Add('Entry count : ' + IntToStr(ElementCount(entries)));
  slOut.Add('');

  entry := ElementByIndex(entries, 0);

  slOut.Add('--- FULL TREE OF ENTRY [0] ---');
  DumpElement(entry, 0, '');
  slOut.Add('');

  slOut.Add('--- ACCESS TESTS (reference field) ---');
  TestPath(entry, 'LVLO - Base Data\Item');
  TestPath(entry, 'LVLO - Base Data\NPC');
  TestPath(entry, 'LVLO - Base Data\Reference');
  TestPath(entry, 'LVLO\Item');
  TestPath(entry, 'LVLO\NPC');
  TestPath(entry, 'LVLO\Reference');
  TestPath(entry, 'Item');
  TestPath(entry, 'NPC');
  TestPath(entry, 'Reference');
  slOut.Add('');

  slOut.Add('--- ACCESS TESTS (level and count) ---');
  slOut.Add('  LVLO - Base Data\Level         = ' +
            IntToStr(GetElementNativeValues(entry, 'LVLO - Base Data\Level')));
  slOut.Add('  LVLO\Level                     = ' +
            IntToStr(GetElementNativeValues(entry, 'LVLO\Level')));
  slOut.Add('  Level                          = ' +
            IntToStr(GetElementNativeValues(entry, 'Level')));
  slOut.Add('  LVLO - Base Data\Count         = ' +
            IntToStr(GetElementNativeValues(entry, 'LVLO - Base Data\Count')));
  slOut.Add('  LVLO\Count                     = ' +
            IntToStr(GetElementNativeValues(entry, 'LVLO\Count')));
  slOut.Add('  LVLO - Base Data\Chance None   = ' +
            IntToStr(GetElementNativeValues(entry, 'LVLO - Base Data\Chance None')));
  slOut.Add('');
end;

function Process(e: IInterface): Integer;
var
  sSig: string;
begin
  Result := 0;
  sSig := Signature(e);

  if sSig = 'LVLI' then begin
    if iDoneLVLI >= iMaxSamples then Exit;
    Inc(iDoneLVLI);
    DumpList(e);
    Exit;
  end;

  if sSig = 'LVLN' then begin
    if iDoneLVLN >= iMaxSamples then Exit;
    Inc(iDoneLVLN);
    DumpList(e);
  end;
end;

function Finalize: Integer;
var
  sPath: string;
begin
  slOut.Add('=== END ===');
  slOut.Add('LVLI sampled: ' + IntToStr(iDoneLVLI));
  slOut.Add('LVLN sampled: ' + IntToStr(iDoneLVLN));

  sPath := ScriptsPath + 'LLDiag.txt';
  slOut.SaveToFile(sPath);
  AddMessage('Diagnostic written to: ' + sPath);
  AddMessage('  LVLI sampled: ' + IntToStr(iDoneLVLI));
  AddMessage('  LVLN sampled: ' + IntToStr(iDoneLVLN));
  slOut.Free;
  Result := 0;
end;

end.
