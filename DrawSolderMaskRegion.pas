{ ===========================================================================
  DrawSolderMaskRegion.pas
  Altium Designer 26.x  –  DelphiScript

  PURPOSE
  -------
  Places solder mask helper primitives outlining the intended opening for
  a selection of one or more connected copper tracks and/or arcs on the
  Top or Bottom signal layer.

  For each selected primitive the outer long edges are always drawn.  The
  closing edges (short perpendicular segments for tracks; end-cap lines for
  arcs) are drawn only at EXTERNAL endpoints — endpoints that are not shared
  with any other selected primitive.  Internal closing edges are suppressed,
  leaving a continuous outer boundary for the entire selection.

  NOTE ON CORNER GAPS
  -------------------
  At junctions between two tracks that meet at an angle, the outer long
  edges of the two rectangles do not share an endpoint exactly.  A small
  open gap will appear at each such corner.  These gaps can be closed
  manually before converting to a region.  Tangentially connected track-arc
  pairs with equal widths do not produce gaps.

  LAYER REQUIREMENT
  -----------------
  All selected primitives must be on the same copper layer (Top or Bottom).

  DIALOG PARAMETERS  (mils)
  -------------------------
  Expansion    – distance beyond the physical edge of each copper primitive
  Left Offset  – inset of the chain's left-end short edge  (tracks only)
  Right Offset – inset of the chain's right-end short edge (tracks only)

  "Left" end  = the external endpoint with the more-negative X coordinate
                (tiebreaker: more-negative Y for vertical chains).
  Offsets are ignored when the corresponding chain end is an arc.

  LIMITATIONS
  -----------
  * Maximum 50 primitives per selection.
  * Endpoint matching uses 0.5 mil tolerance.
  * Corner gaps at angled track-track junctions must be closed manually.
  * Branched selections (more than 2 external endpoints) are accepted but
    offsets are not applied (the chain topology is ambiguous).

  =========================================================================== }


{ ---------------------------------------------------------------------------
  MakeHelperTrack — places one track segment and returns it
  --------------------------------------------------------------------------- }
function MakeHelperTrack(Board       : IPCB_Board;
                         TargetLayer : TLayer;
                         X1, Y1      : TCoord;
                         X2, Y2      : TCoord;
                         LineWidth   : TCoord) : IPCB_Track;
var
  T : IPCB_Track;
begin
  T       := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
  T.X1    := X1;  T.Y1 := Y1;
  T.X2    := X2;  T.Y2 := Y2;
  T.Layer := TargetLayer;
  T.Width := LineWidth;
  Board.AddPCBObject(T);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, T.I_ObjectAddress);
  Result := T;
end;


{ ---------------------------------------------------------------------------
  MakeHelperArc — places one arc and returns it
  --------------------------------------------------------------------------- }
function MakeHelperArc(Board         : IPCB_Board;
                       TargetLayer   : TLayer;
                       CX, CY        : TCoord;
                       ArcRadius     : TCoord;
                       StartAngleDeg : Double;
                       EndAngleDeg   : Double;
                       LineWidth     : TCoord) : IPCB_Arc;
var
  A : IPCB_Arc;
begin
  A            := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
  A.XCenter    := CX;  A.YCenter := CY;
  A.Radius     := ArcRadius;
  A.StartAngle := StartAngleDeg;
  A.EndAngle   := EndAngleDeg;
  A.Layer      := TargetLayer;
  A.LineWidth  := LineWidth;
  Board.AddPCBObject(A);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, A.I_ObjectAddress);
  Result := A;
end;


{ ---------------------------------------------------------------------------
  ShowParamDialog
  --------------------------------------------------------------------------- }
procedure ShowParamDialog(var Expansion   : Double;
                          var LeftOffset  : Double;
                          var RightOffset : Double;
                          var Cancelled   : Boolean);
var
  Dlg          : TForm;
  LblExp, LblLeft, LblRight, LblNote : TLabel;
  EdtExp, EdtLeft, EdtRight : TEdit;
  BtnOK, BtnCancel : TButton;
  ParsedVal    : Double;
  ValidationOK : Boolean;
begin
  Expansion := 0;  LeftOffset := 0;  RightOffset := 0;  Cancelled := True;
  Dlg := TForm.Create(Nil);
  try
    Dlg.Caption     := 'Solder Mask Region – Parameters';
    Dlg.Width       := 360;
    Dlg.Height      := 270;
    Dlg.Position    := poScreenCenter;
    Dlg.BorderStyle := bsDialog;

    LblExp := TLabel.Create(Dlg);  LblExp.Parent := Dlg;
    LblExp.Caption := 'Expansion (mils):';  LblExp.Left := 16;  LblExp.Top := 22;

    EdtExp := TEdit.Create(Dlg);  EdtExp.Parent := Dlg;
    EdtExp.Left := 210;  EdtExp.Top := 18;  EdtExp.Width := 110;  EdtExp.Text := '0';

    LblLeft := TLabel.Create(Dlg);  LblLeft.Parent := Dlg;
    LblLeft.Caption := 'Left offset, mils (tracks only):';
    LblLeft.Left := 16;  LblLeft.Top := 62;

    EdtLeft := TEdit.Create(Dlg);  EdtLeft.Parent := Dlg;
    EdtLeft.Left := 210;  EdtLeft.Top := 58;  EdtLeft.Width := 110;  EdtLeft.Text := '0';

    LblRight := TLabel.Create(Dlg);  LblRight.Parent := Dlg;
    LblRight.Caption := 'Right offset, mils (tracks only):';
    LblRight.Left := 16;  LblRight.Top := 102;

    EdtRight := TEdit.Create(Dlg);  EdtRight.Parent := Dlg;
    EdtRight.Left := 210;  EdtRight.Top := 98;  EdtRight.Width := 110;  EdtRight.Text := '0';

    LblNote := TLabel.Create(Dlg);  LblNote.Parent := Dlg;
    LblNote.Caption := '"Left" = chain end with more-negative X coordinate.';
    LblNote.Left := 16;  LblNote.Top := 142;  LblNote.Width := 320;

    BtnOK := TButton.Create(Dlg);  BtnOK.Parent := Dlg;
    BtnOK.Caption := 'OK';  BtnOK.Left := 150;  BtnOK.Top := 192;
    BtnOK.Width := 80;  BtnOK.ModalResult := mrOK;  BtnOK.Default := True;

    BtnCancel := TButton.Create(Dlg);  BtnCancel.Parent := Dlg;
    BtnCancel.Caption := 'Cancel';  BtnCancel.Left := 244;  BtnCancel.Top := 192;
    BtnCancel.Width := 80;  BtnCancel.ModalResult := mrCancel;  BtnCancel.Cancel := True;

    ValidationOK := False;
    while not ValidationOK do
    begin
      if Dlg.ShowModal <> mrOK then Exit;
      ValidationOK := True;

      ParsedVal := StrToFloatDef(EdtExp.Text, -1);
      if ParsedVal < 0 then begin ShowMessage('Expansion must be a non-negative number.'); ValidationOK := False; Continue; end;
      Expansion := ParsedVal;

      ParsedVal := StrToFloatDef(EdtLeft.Text, -1);
      if ParsedVal < 0 then begin ShowMessage('Left offset must be a non-negative number.'); ValidationOK := False; Continue; end;
      LeftOffset := ParsedVal;

      ParsedVal := StrToFloatDef(EdtRight.Text, -1);
      if ParsedVal < 0 then begin ShowMessage('Right offset must be a non-negative number.'); ValidationOK := False; Continue; end;
      RightOffset := ParsedVal;
    end;
    Cancelled := False;
  finally
    Dlg.Free;
  end;
end;


{ ===========================================================================
  DrawSolderMaskRegion  –  SCRIPT ENTRY POINT
  =========================================================================== }
procedure DrawSolderMaskRegion;
const
  MAX_PRIMS = 50;
  ENDPT_TOL = 0.5;   { endpoint-matching tolerance in mils }

var
  Board       : IPCB_Board;
  TargetLayer : TLayer;
  Expansion   : Double;
  LeftOffset  : Double;
  RightOffset : Double;
  Cancelled   : Boolean;

  { ---- Primitive parallel arrays ---- }
  PrimCount   : Integer;
  { true = track, false = arc }
  PrimIsTrack : array[0..MAX_PRIMS-1] of Boolean;
  PrimTrack   : array[0..MAX_PRIMS-1] of IPCB_Track;
  PrimArc     : array[0..MAX_PRIMS-1] of IPCB_Arc;
  { Primitive layer (all should be the same copper layer) }
  PrimLayer   : array[0..MAX_PRIMS-1] of TLayer;
  { Endpoint coordinates in TCoord (natural: X1/Y1 for tracks, StartAngle point for arcs) }
  PrimSX, PrimSY : array[0..MAX_PRIMS-1] of TCoord;
  PrimEX, PrimEY : array[0..MAX_PRIMS-1] of TCoord;
  { Adjacency: index of the primitive connected at each end; -1 = external }
  PrimSAdj, PrimEAdj : array[0..MAX_PRIMS-1] of Integer;

  { ---- External-endpoint arrays (up to MAX_PRIMS*2 theoretical, 10 typical) ---- }
  ExtCount             : Integer;
  ExtX, ExtY           : array[0..9] of TCoord;
  ExtPrimIdx           : array[0..9] of Integer;
  ExtIsStart           : array[0..9] of Boolean;

  { ---- Chain left/right identification ---- }
  LeftPrimIdx, RightPrimIdx : Integer;
  LeftIsStart, RightIsStart : Boolean;
  SimpleChain               : Boolean;   { exactly 2 external endpoints }

  { ---- Loop / temp variables ---- }
  Iter       : IPCB_BoardIterator;
  Obj        : IPCB_Primitive;
  i, j, k    : Integer;
  Tol        : TCoord;
  FoundLayer : TLayer;
  AllSame    : Boolean;

  { ---- Per-primitive geometry (track) ---- }
  SXm, SYm, EXm, EYm : Double;   { endpoints in mils }
  deltaX, deltaY      : Double;
  TrackAngle          : Double;
  Ux, Uy, Vx, Vy     : Double;
  Half, s_lo, e_ro    : Double;
  ax, ay, bx, by      : Double;
  cx, cy, dx, dy      : Double;
  LineW               : TCoord;

  { ---- Per-primitive geometry (arc) ---- }
  HalfW              : TCoord;
  OuterRadius        : TCoord;
  InnerRadius        : TCoord;
  StartRad, EndRad   : Double;
  OStartX, OStartY   : TCoord;
  OEndX,   OEndY     : TCoord;
  IStartX, IStartY   : TCoord;
  IEndX,   IEndY     : TCoord;

begin
  { ------------------------------------------------------------------ }
  { 1. Obtain active PCB document                                        }
  { ------------------------------------------------------------------ }
  Board := PCBServer.GetCurrentPCBBoard;
  if Board = Nil then
  begin
    ShowMessage('Error: No PCB document is currently active.');
    Exit;
  end;

  { ------------------------------------------------------------------ }
  { 2. Collect all selected tracks and arcs on a copper layer           }
  { ------------------------------------------------------------------ }
  PrimCount := 0;

  Iter := Board.BoardIterator_Create;
  Iter.AddFilter_ObjectSet(MkSet(eTrackObject));
  Iter.AddFilter_LayerSet(AllLayers);
  Obj := Iter.FirstPCBObject;
  while (Obj <> Nil) and (PrimCount < MAX_PRIMS) do
  begin
    if Obj.Selected then
      if (Obj.Layer = eTopLayer) or (Obj.Layer = eBottomLayer) then
      begin
        PrimIsTrack[PrimCount] := True;
        PrimTrack[PrimCount]   := Obj;
        PrimArc[PrimCount]     := Nil;
        PrimLayer[PrimCount]   := Obj.Layer;
        PrimSX[PrimCount]      := Obj.X1;
        PrimSY[PrimCount]      := Obj.Y1;
        PrimEX[PrimCount]      := Obj.X2;
        PrimEY[PrimCount]      := Obj.Y2;
        Inc(PrimCount);
      end;
    Obj := Iter.NextPCBObject;
  end;
  Board.BoardIterator_Destroy(Iter);

  Iter := Board.BoardIterator_Create;
  Iter.AddFilter_ObjectSet(MkSet(eArcObject));
  Iter.AddFilter_LayerSet(AllLayers);
  Obj := Iter.FirstPCBObject;
  while (Obj <> Nil) and (PrimCount < MAX_PRIMS) do
  begin
    if Obj.Selected then
      if (Obj.Layer = eTopLayer) or (Obj.Layer = eBottomLayer) then
      begin
        PrimIsTrack[PrimCount] := False;
        PrimTrack[PrimCount]   := Nil;
        PrimArc[PrimCount]     := Obj;
        PrimLayer[PrimCount]   := Obj.Layer;
        { Arc start/end points in TCoord }
        StartRad := Obj.StartAngle * Pi / 180.0;
        EndRad   := Obj.EndAngle   * Pi / 180.0;
        PrimSX[PrimCount] := Round(Obj.XCenter + Obj.Radius * Cos(StartRad));
        PrimSY[PrimCount] := Round(Obj.YCenter + Obj.Radius * Sin(StartRad));
        PrimEX[PrimCount] := Round(Obj.XCenter + Obj.Radius * Cos(EndRad));
        PrimEY[PrimCount] := Round(Obj.YCenter + Obj.Radius * Sin(EndRad));
        Inc(PrimCount);
      end;
    Obj := Iter.NextPCBObject;
  end;
  Board.BoardIterator_Destroy(Iter);

  { ---- Validate ---- }
  if PrimCount = 0 then
  begin
    ShowMessage(
      'Error: No tracks or arcs selected on the Top or Bottom copper layer.' + #13#10 +
      'Please select one or more connected tracks/arcs and re-run.');
    Exit;
  end;

  if PrimCount > MAX_PRIMS then
  begin
    ShowMessage('Error: Selection contains more than ' + IntToStr(MAX_PRIMS) + ' primitives.');
    Exit;
  end;

  { All primitives must be on the same copper layer }
  FoundLayer := PrimLayer[0];
  AllSame := True;
  for i := 1 to PrimCount - 1 do
    if PrimLayer[i] <> FoundLayer then begin AllSame := False; Break; end;

  if not AllSame then
  begin
    ShowMessage(
      'Error: All selected primitives must be on the same copper layer.' + #13#10 +
      'Mixed Top/Bottom selections are not supported.');
    Exit;
  end;

  { ------------------------------------------------------------------ }
  { 3. Resolve target solder-mask layer                                  }
  { ------------------------------------------------------------------ }
  if FoundLayer = eTopLayer then
    TargetLayer := eTopSolder
  else
    TargetLayer := eBottomSolder;

  { ------------------------------------------------------------------ }
  { 4. Collect parameters                                                }
  { ------------------------------------------------------------------ }
  ShowParamDialog(Expansion, LeftOffset, RightOffset, Cancelled);
  if Cancelled then Exit;

  { ------------------------------------------------------------------ }
  { 5. Build endpoint connectivity                                        }
  { ------------------------------------------------------------------ }
  { Initialise: all endpoints are external }
  for i := 0 to PrimCount - 1 do
  begin
    PrimSAdj[i] := -1;
    PrimEAdj[i] := -1;
  end;

  Tol := MilsToCoord(ENDPT_TOL);

  for i := 0 to PrimCount - 2 do
    for j := i + 1 to PrimCount - 1 do
    begin
      { Test all four endpoint-pair combinations }

      { i.start — j.start }
      if (Abs(PrimSX[i] - PrimSX[j]) <= Tol) and
         (Abs(PrimSY[i] - PrimSY[j]) <= Tol) then
      begin
        PrimSAdj[i] := j;  PrimSAdj[j] := i;
      end;

      { i.start — j.end }
      if (Abs(PrimSX[i] - PrimEX[j]) <= Tol) and
         (Abs(PrimSY[i] - PrimEY[j]) <= Tol) then
      begin
        PrimSAdj[i] := j;  PrimEAdj[j] := i;
      end;

      { i.end — j.start }
      if (Abs(PrimEX[i] - PrimSX[j]) <= Tol) and
         (Abs(PrimEY[i] - PrimSY[j]) <= Tol) then
      begin
        PrimEAdj[i] := j;  PrimSAdj[j] := i;
      end;

      { i.end — j.end }
      if (Abs(PrimEX[i] - PrimEX[j]) <= Tol) and
         (Abs(PrimEY[i] - PrimEY[j]) <= Tol) then
      begin
        PrimEAdj[i] := j;  PrimEAdj[j] := i;
      end;
    end;

  { ------------------------------------------------------------------ }
  { 6. Find external endpoints and identify left/right chain ends        }
  { ------------------------------------------------------------------ }
  ExtCount := 0;
  for i := 0 to PrimCount - 1 do
  begin
    if (PrimSAdj[i] = -1) and (ExtCount < 10) then
    begin
      ExtX[ExtCount]       := PrimSX[i];
      ExtY[ExtCount]       := PrimSY[i];
      ExtPrimIdx[ExtCount] := i;
      ExtIsStart[ExtCount] := True;
      Inc(ExtCount);
    end;
    if (PrimEAdj[i] = -1) and (ExtCount < 10) then
    begin
      ExtX[ExtCount]       := PrimEX[i];
      ExtY[ExtCount]       := PrimEY[i];
      ExtPrimIdx[ExtCount] := i;
      ExtIsStart[ExtCount] := False;
      Inc(ExtCount);
    end;
  end;

  SimpleChain      := (ExtCount = 2);
  LeftPrimIdx      := -1;
  RightPrimIdx     := -1;
  LeftIsStart      := False;
  RightIsStart     := False;

  if SimpleChain then
  begin
    { Assign left = more-negative X; tiebreak on more-negative Y }
    if (ExtX[0] < ExtX[1]) or
       ((ExtX[0] = ExtX[1]) and (ExtY[0] < ExtY[1])) then
    begin
      LeftPrimIdx  := ExtPrimIdx[0];  LeftIsStart  := ExtIsStart[0];
      RightPrimIdx := ExtPrimIdx[1];  RightIsStart := ExtIsStart[1];
    end
    else
    begin
      LeftPrimIdx  := ExtPrimIdx[1];  LeftIsStart  := ExtIsStart[1];
      RightPrimIdx := ExtPrimIdx[0];  RightIsStart := ExtIsStart[0];
    end;
  end;

  { ------------------------------------------------------------------ }
  { 7. Place all helper primitives                                        }
  { ------------------------------------------------------------------ }
  PCBServer.PreProcess;

  for i := 0 to PrimCount - 1 do
  begin
    { --- Determine per-end offsets (mils) ---
      An offset applies only when:
        (a) the end is external (no adjacent primitive),
        (b) this primitive is a track,
        (c) this end is the chain's left or right end (SimpleChain only),
        (d) LeftOffset / RightOffset is non-zero. }
    s_lo := 0;
    e_ro := 0;

    if PrimIsTrack[i] and SimpleChain then
    begin
      if (PrimSAdj[i] = -1) then   { start is external }
      begin
        if (i = LeftPrimIdx)  and LeftIsStart  then s_lo := LeftOffset;
        if (i = RightPrimIdx) and RightIsStart then s_lo := RightOffset;
      end;
      if (PrimEAdj[i] = -1) then   { end is external }
      begin
        if (i = LeftPrimIdx)  and (not LeftIsStart)  then e_ro := LeftOffset;
        if (i = RightPrimIdx) and (not RightIsStart) then e_ro := RightOffset;
      end;
    end;

    { ============================================================ }
    { TRACK case                                                    }
    { ============================================================ }
    if PrimIsTrack[i] then
    begin
      { Convert endpoints to mils }
      SXm := CoordToMils(PrimSX[i]);  SYm := CoordToMils(PrimSY[i]);
      EXm := CoordToMils(PrimEX[i]);  EYm := CoordToMils(PrimEY[i]);

      deltaX := EXm - SXm;
      deltaY := EYm - SYm;

      if (Abs(deltaX) < 0.001) and (Abs(deltaY) < 0.001) then
        Continue;   { skip zero-length track }

      TrackAngle := ArcTan2(deltaY, deltaX);
      Ux :=  Cos(TrackAngle);
      Uy :=  Sin(TrackAngle);
      Vx :=  Cos(TrackAngle + Pi / 2);
      Vy :=  Sin(TrackAngle + Pi / 2);

      Half := CoordToMils(PrimTrack[i].Width) / 2.0 + Expansion;

      { Corner coordinates (mils).
        s_lo moves the start short edge inward (along Ux toward E).
        e_ro moves the end short edge inward (along -Ux toward S). }
      ax := SXm + s_lo * Ux + Half * Vx;   { top-left  }
      ay := SYm + s_lo * Uy + Half * Vy;
      bx := EXm - e_ro * Ux + Half * Vx;   { top-right }
      by := EYm - e_ro * Uy + Half * Vy;
      cx := EXm - e_ro * Ux - Half * Vx;   { bot-right }
      cy := EYm - e_ro * Uy - Half * Vy;
      dx := SXm + s_lo * Ux - Half * Vx;   { bot-left  }
      dy := SYm + s_lo * Uy - Half * Vy;

      LineW := MilsToCoord(1);

      { Top long edge: A → B (always) }
      MakeHelperTrack(Board, TargetLayer,
        MilsToCoord(ax), MilsToCoord(ay), MilsToCoord(bx), MilsToCoord(by), LineW);

      { Bottom long edge: D → C (always) }
      MakeHelperTrack(Board, TargetLayer,
        MilsToCoord(dx), MilsToCoord(dy), MilsToCoord(cx), MilsToCoord(cy), LineW);

      { Left short edge: A → D (only if start is external) }
      if PrimSAdj[i] = -1 then
        MakeHelperTrack(Board, TargetLayer,
          MilsToCoord(ax), MilsToCoord(ay), MilsToCoord(dx), MilsToCoord(dy), LineW);

      { Right short edge: B → C (only if end is external) }
      if PrimEAdj[i] = -1 then
        MakeHelperTrack(Board, TargetLayer,
          MilsToCoord(bx), MilsToCoord(by), MilsToCoord(cx), MilsToCoord(cy), LineW);
    end

    { ============================================================ }
    { ARC case                                                      }
    { ============================================================ }
    else
    begin
      HalfW       := PrimArc[i].LineWidth div 2;
      OuterRadius := PrimArc[i].Radius + HalfW + MilsToCoord(Expansion);
      InnerRadius := PrimArc[i].Radius - HalfW - MilsToCoord(Expansion);

      if InnerRadius <= 0 then
      begin
        ShowMessage(
          'Warning: Expansion too large for arc ' + IntToStr(i) +
          ' — inner radius would be zero or negative.  Arc skipped.');
        Continue;
      end;

      StartRad := PrimArc[i].StartAngle * Pi / 180.0;
      EndRad   := PrimArc[i].EndAngle   * Pi / 180.0;

      OStartX := Round(PrimArc[i].XCenter + OuterRadius * Cos(StartRad));
      OStartY := Round(PrimArc[i].YCenter + OuterRadius * Sin(StartRad));
      OEndX   := Round(PrimArc[i].XCenter + OuterRadius * Cos(EndRad));
      OEndY   := Round(PrimArc[i].YCenter + OuterRadius * Sin(EndRad));

      IStartX := Round(PrimArc[i].XCenter + InnerRadius * Cos(StartRad));
      IStartY := Round(PrimArc[i].YCenter + InnerRadius * Sin(StartRad));
      IEndX   := Round(PrimArc[i].XCenter + InnerRadius * Cos(EndRad));
      IEndY   := Round(PrimArc[i].YCenter + InnerRadius * Sin(EndRad));

      { Outer arc (always) }
      MakeHelperArc(Board, TargetLayer,
        PrimArc[i].XCenter, PrimArc[i].YCenter, OuterRadius,
        PrimArc[i].StartAngle, PrimArc[i].EndAngle, MilsToCoord(0.5));

      { Inner arc (always) }
      MakeHelperArc(Board, TargetLayer,
        PrimArc[i].XCenter, PrimArc[i].YCenter, InnerRadius,
        PrimArc[i].StartAngle, PrimArc[i].EndAngle, MilsToCoord(0.5));

      { Start closing line: outer-start → inner-start (only if start is external) }
      if PrimSAdj[i] = -1 then
        MakeHelperTrack(Board, TargetLayer,
          OStartX, OStartY, IStartX, IStartY, MilsToCoord(1));

      { End closing line: outer-end → inner-end (only if end is external) }
      if PrimEAdj[i] = -1 then
        MakeHelperTrack(Board, TargetLayer,
          OEndX, OEndY, IEndX, IEndY, MilsToCoord(1));
    end;

  end; { for i }

  PCBServer.PostProcess;
  Board.ViewManager_FullUpdate;

  ShowMessage(
    IntToStr(PrimCount) + ' primitive(s) processed.' + #13#10 +
    'Helpers placed on: ' + Board.LayerName(TargetLayer) + #13#10 +
    #13#10 +
    'Internal closing edges have been suppressed.' + #13#10 +
    'Close any corner gaps manually, then convert to a region.');
end;
