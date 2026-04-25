{ ===========================================================================
  DrawSolderMaskRegion.pas
  Altium Designer 26.x  –  DelphiScript

  PURPOSE
  -------
  Places a filled solder-mask opening region aligned to a selected copper
  track or arc on the Top or Bottom signal layer.

  TRACK CASE
  ----------
  A rotated rectangle is drawn as four helper track segments, converted to
  a region via Tools → Convert → Create Region from Selected Primitives,
  and the helpers are then deleted.

  ARC CASE
  --------
  Two concentric helper arcs plus two closing helper tracks form the region
  boundary.  After conversion the helpers are deleted and the region's
  Arc Approximation is set to 0.001 mil for smooth rendering.

  PRE-CONDITIONS
  --------------
  Exactly one track OR one arc must be selected on the Top or Bottom copper
  layer before running the script.

  DIALOG PARAMETERS  (mils)
  -------------------------
  Expansion    – distance beyond the physical edge of the copper primitive
  Left Offset  – inset of the left/start short edge along trace (tracks only)
  Right Offset – inset of the right/end short edge along trace (tracks only)

  LEFT / RIGHT ENDPOINT CONVENTION  (tracks)
  ------------------------------------------
  "Left"  = endpoint with the more-negative X coordinate.
  Tiebreaker for exactly vertical tracks (X1 = X2):
    "Left"  = more-negative Y endpoint (bottom in Altium's upward-Y system)
    "Right" = more-positive Y endpoint (top)

  UNDO
  ----
  Helper creation, helper deletion, and arc-approximation edits each occupy
  their own PreProcess/PostProcess transaction.  The region conversion uses
  RunProcess which manages its own transaction.  All steps can be undone
  individually with Ctrl+Z.

  =========================================================================== }


{ ---------------------------------------------------------------------------
  MakeHelperTrack
  --------------------------------------------------------------------------- }
function MakeHelperTrack(Board       : IPCB_Board;
                         TargetLayer : TLayer;
                         X1, Y1      : TCoord;
                         X2, Y2      : TCoord;
                         LineWidth   : TCoord) : IPCB_Track;
var
  T : IPCB_Track;
begin
  T         := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
  T.X1      := X1;
  T.Y1      := Y1;
  T.X2      := X2;
  T.Y2      := Y2;
  T.Layer   := TargetLayer;
  T.Width   := LineWidth;

  Board.AddPCBObject(T);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, T.I_ObjectAddress);

  Result := T;
end;


{ ---------------------------------------------------------------------------
  MakeHelperArc
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
  A.XCenter    := CX;
  A.YCenter    := CY;
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
  GetSelectedObject
  --------------------------------------------------------------------------- }
function GetSelectedObject(Board     : IPCB_Board;
                           var Track : IPCB_Track;
                           var Arc   : IPCB_Arc) : Boolean;
var
  Iter     : IPCB_BoardIterator;
  Obj      : IPCB_Primitive;
  SelCount : Integer;
begin
  Result   := False;
  Track    := Nil;
  Arc      := Nil;
  SelCount := 0;

  Iter := Board.BoardIterator_Create;
  Iter.AddFilter_ObjectSet(MkSet(eTrackObject));
  Iter.AddFilter_LayerSet(AllLayers);
  Obj := Iter.FirstPCBObject;
  while Obj <> Nil do
  begin
    if Obj.Selected then
      if (Obj.Layer = eTopLayer) or (Obj.Layer = eBottomLayer) then
      begin
        Inc(SelCount);
        Track := Obj;
      end;
    Obj := Iter.NextPCBObject;
  end;
  Board.BoardIterator_Destroy(Iter);

  Iter := Board.BoardIterator_Create;
  Iter.AddFilter_ObjectSet(MkSet(eArcObject));
  Iter.AddFilter_LayerSet(AllLayers);
  Obj := Iter.FirstPCBObject;
  while Obj <> Nil do
  begin
    if Obj.Selected then
      if (Obj.Layer = eTopLayer) or (Obj.Layer = eBottomLayer) then
      begin
        Inc(SelCount);
        Arc := Obj;
      end;
    Obj := Iter.NextPCBObject;
  end;
  Board.BoardIterator_Destroy(Iter);

  if SelCount = 0 then
  begin
    ShowMessage(
      'Error: No qualifying object selected.' + #13#10 + #13#10 +
      'Please select exactly one track or arc on the Top or' + #13#10 +
      'Bottom copper layer, then re-run the script.');
    Exit;
  end;

  if SelCount > 1 then
  begin
    ShowMessage(
      'Error: Multiple objects are selected (' + IntToStr(SelCount) + ').' + #13#10 + #13#10 +
      'Please select exactly one track or arc and re-run the script.');
    Exit;
  end;

  if (Track <> Nil) and (Arc <> Nil) then Arc := Nil;

  Result := True;
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
  LblExp       : TLabel;
  LblLeft      : TLabel;
  LblRight     : TLabel;
  LblNote      : TLabel;
  EdtExp       : TEdit;
  EdtLeft      : TEdit;
  EdtRight     : TEdit;
  BtnOK        : TButton;
  BtnCancel    : TButton;
  ParsedVal    : Double;
  ValidationOK : Boolean;
begin
  Expansion   := 0;
  LeftOffset  := 0;
  RightOffset := 0;
  Cancelled   := True;

  Dlg := TForm.Create(Nil);
  try
    Dlg.Caption     := 'Solder Mask Region – Parameters';
    Dlg.Width       := 360;
    Dlg.Height      := 270;
    Dlg.Position    := poScreenCenter;
    Dlg.BorderStyle := bsDialog;

    LblExp         := TLabel.Create(Dlg);
    LblExp.Parent  := Dlg;
    LblExp.Caption := 'Expansion (mils):';
    LblExp.Left    := 16;
    LblExp.Top     := 22;

    EdtExp        := TEdit.Create(Dlg);
    EdtExp.Parent := Dlg;
    EdtExp.Left   := 210;
    EdtExp.Top    := 18;
    EdtExp.Width  := 110;
    EdtExp.Text   := '0';

    LblLeft         := TLabel.Create(Dlg);
    LblLeft.Parent  := Dlg;
    LblLeft.Caption := 'Left offset, mils (tracks only):';
    LblLeft.Left    := 16;
    LblLeft.Top     := 62;

    EdtLeft        := TEdit.Create(Dlg);
    EdtLeft.Parent := Dlg;
    EdtLeft.Left   := 210;
    EdtLeft.Top    := 58;
    EdtLeft.Width  := 110;
    EdtLeft.Text   := '0';

    LblRight         := TLabel.Create(Dlg);
    LblRight.Parent  := Dlg;
    LblRight.Caption := 'Right offset, mils (tracks only):';
    LblRight.Left    := 16;
    LblRight.Top     := 102;

    EdtRight        := TEdit.Create(Dlg);
    EdtRight.Parent := Dlg;
    EdtRight.Left   := 210;
    EdtRight.Top    := 98;
    EdtRight.Width  := 110;
    EdtRight.Text   := '0';

    LblNote         := TLabel.Create(Dlg);
    LblNote.Parent  := Dlg;
    LblNote.Caption := '"Left" = more-negative X (or bottom for vertical tracks).';
    LblNote.Left    := 16;
    LblNote.Top     := 142;
    LblNote.Width   := 320;

    BtnOK             := TButton.Create(Dlg);
    BtnOK.Parent      := Dlg;
    BtnOK.Caption     := 'OK';
    BtnOK.Left        := 150;
    BtnOK.Top         := 192;
    BtnOK.Width       := 80;
    BtnOK.ModalResult := mrOK;
    BtnOK.Default     := True;

    BtnCancel             := TButton.Create(Dlg);
    BtnCancel.Parent      := Dlg;
    BtnCancel.Caption     := 'Cancel';
    BtnCancel.Left        := 244;
    BtnCancel.Top         := 192;
    BtnCancel.Width       := 80;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Cancel      := True;

    ValidationOK := False;
    while not ValidationOK do
    begin
      if Dlg.ShowModal <> mrOK then Exit;
      ValidationOK := True;

      ParsedVal := StrToFloatDef(EdtExp.Text, -1);
      if ParsedVal < 0 then
      begin
        ShowMessage('Expansion must be a non-negative number (e.g. 25 or 25.4).');
        ValidationOK := False; Continue;
      end;
      Expansion := ParsedVal;

      ParsedVal := StrToFloatDef(EdtLeft.Text, -1);
      if ParsedVal < 0 then
      begin
        ShowMessage('Left offset must be a non-negative number.');
        ValidationOK := False; Continue;
      end;
      LeftOffset := ParsedVal;

      ParsedVal := StrToFloatDef(EdtRight.Text, -1);
      if ParsedVal < 0 then
      begin
        ShowMessage('Right offset must be a non-negative number.');
        ValidationOK := False; Continue;
      end;
      RightOffset := ParsedVal;
    end;

    Cancelled := False;
  finally
    Dlg.Free;
  end;
end;


{ ---------------------------------------------------------------------------
  FindNewRegion
  After RunProcess('PCB:CreateRegionFromSelectedPrimitives'), Altium leaves
  the newly created region selected.  This function scans for a selected
  region on TargetLayer and returns it (or Nil if none found).
  --------------------------------------------------------------------------- }
function FindNewRegion(Board       : IPCB_Board;
                       TargetLayer : TLayer) : IPCB_Region;
var
  Iter : IPCB_BoardIterator;
  Obj  : IPCB_Primitive;
begin
  Result := Nil;

  Iter := Board.BoardIterator_Create;
  Iter.AddFilter_ObjectSet(MkSet(eRegionObject));
  Iter.AddFilter_LayerSet(AllLayers);

  Obj := Iter.FirstPCBObject;
  while Obj <> Nil do
  begin
    if Obj.Selected and (Obj.Layer = TargetLayer) then
    begin
      Result := Obj;
      Break;
    end;
    Obj := Iter.NextPCBObject;
  end;

  Board.BoardIterator_Destroy(Iter);
end;


{ ---------------------------------------------------------------------------
  DrawTrackHelpers
  Full flow for the track case:
    1. Compute rotated rectangle corners.
    2. Place four helper track segments in a PreProcess/PostProcess block.
    3. Deselect all, select only the four helpers, refresh.
    4. RunProcess to convert to a region  (OUTSIDE any Pre/PostProcess block).
    5. Delete the four helpers in a PreProcess/PostProcess block.
  --------------------------------------------------------------------------- }
procedure DrawTrackHelpers(Board       : IPCB_Board;
                           Track       : IPCB_Track;
                           TargetLayer : TLayer;
                           Expansion   : Double;
                           LeftOffset  : Double;
                           RightOffset : Double);
var
  Lx, Ly, Rx, Ry : Double;
  dX, dY         : Double;
  TrackAngle     : Double;
  ux, uy, vx, vy : Double;
  Half, Lo, Ro   : Double;
  ax, ay         : Double;
  bx, by         : Double;
  cx, cy         : Double;
  dx, dy         : Double;
  LineW          : TCoord;
  T1, T2, T3, T4 : IPCB_Track;
begin
  { Assign left/right endpoints (mils) }
  if (Track.X1 < Track.X2) or
     ((Track.X1 = Track.X2) and (Track.Y1 < Track.Y2)) then
  begin
    Lx := CoordToMils(Track.X1);  Ly := CoordToMils(Track.Y1);
    Rx := CoordToMils(Track.X2);  Ry := CoordToMils(Track.Y2);
  end
  else
  begin
    Lx := CoordToMils(Track.X2);  Ly := CoordToMils(Track.Y2);
    Rx := CoordToMils(Track.X1);  Ry := CoordToMils(Track.Y1);
  end;

  dX := Rx - Lx;
  dY := Ry - Ly;

  if (Abs(dX) < 0.001) and (Abs(dY) < 0.001) then
  begin
    ShowMessage('Warning: The selected track has zero (or near-zero) length. Skipped.');
    Exit;
  end;

  TrackAngle := ArcTan2(dY, dX);
  ux :=  Cos(TrackAngle);
  uy :=  Sin(TrackAngle);
  vx :=  Cos(TrackAngle + Pi / 2);
  vy :=  Sin(TrackAngle + Pi / 2);

  Half := CoordToMils(Track.Width) / 2.0 + Expansion;
  Lo   := LeftOffset;
  Ro   := RightOffset;

  ax := Lx + Lo * ux + Half * vx;  ay := Ly + Lo * uy + Half * vy;
  bx := Rx - Ro * ux + Half * vx;  by := Ry - Ro * uy + Half * vy;
  cx := Rx - Ro * ux - Half * vx;  cy := Ry - Ro * uy - Half * vy;
  dx := Lx + Lo * ux - Half * vx;  dy := Ly + Lo * uy - Half * vy;

  LineW := MilsToCoord(1);

  { --- Step 1: create helper tracks --- }
  PCBServer.PreProcess;
  T1 := MakeHelperTrack(Board, TargetLayer,
          MilsToCoord(ax), MilsToCoord(ay), MilsToCoord(bx), MilsToCoord(by), LineW);
  T2 := MakeHelperTrack(Board, TargetLayer,
          MilsToCoord(bx), MilsToCoord(by), MilsToCoord(cx), MilsToCoord(cy), LineW);
  T3 := MakeHelperTrack(Board, TargetLayer,
          MilsToCoord(cx), MilsToCoord(cy), MilsToCoord(dx), MilsToCoord(dy), LineW);
  T4 := MakeHelperTrack(Board, TargetLayer,
          MilsToCoord(dx), MilsToCoord(dy), MilsToCoord(ax), MilsToCoord(ay), LineW);
  PCBServer.PostProcess;
  Board.ViewManager_FullUpdate;

  { --- Step 2: select only the four helpers --- }
  ResetParameters;
  RunProcess('PCB:DeselAll');
  T1.Selected := True;
  T2.Selected := True;
  T3.Selected := True;
  T4.Selected := True;
  Board.ViewManager_FullUpdate;

  { --- Step 3: convert to region (RunProcess manages its own transaction) --- }
  ResetParameters;
  RunProcess('PCB:CreateRegionFromSelectedPrimitives');
  Board.ViewManager_FullUpdate;

  { --- Step 4: delete helper tracks --- }
  PCBServer.PreProcess;
  Board.RemovePCBObject(T1);
  Board.RemovePCBObject(T2);
  Board.RemovePCBObject(T3);
  Board.RemovePCBObject(T4);
  PCBServer.PostProcess;
  Board.ViewManager_FullUpdate;
end;


{ ---------------------------------------------------------------------------
  DrawArcHelpers
  Full flow for the arc case:
    1. Place two concentric helper arcs and two closing helper tracks in a
       PreProcess/PostProcess block.
    2. Deselect all, select only the four helpers, refresh.
    3. RunProcess to convert to a region  (OUTSIDE any Pre/PostProcess block).
    4. Find the newly created region (it will be selected after RunProcess).
    5. Set ArcApproximation = 0.001 mil on the region.
    6. Delete the four helpers in a PreProcess/PostProcess block.
  --------------------------------------------------------------------------- }
procedure DrawArcHelpers(Board          : IPCB_Board;
                         Arc            : IPCB_Arc;
                         TargetLayer    : TLayer;
                         ExpansionCoord : TCoord);
var
  HalfWidth        : TCoord;
  OuterRadius      : TCoord;
  InnerRadius      : TCoord;
  StartRad         : Double;
  EndRad           : Double;
  OStartX, OStartY : TCoord;
  OEndX,   OEndY   : TCoord;
  IStartX, IStartY : TCoord;
  IEndX,   IEndY   : TCoord;
  OuterArcHelper   : IPCB_Arc;
  InnerArcHelper   : IPCB_Arc;
  StartLine        : IPCB_Track;
  EndLine          : IPCB_Track;
  NewRegion        : IPCB_Region;
begin
  HalfWidth   := Arc.LineWidth div 2;
  OuterRadius := Arc.Radius + HalfWidth + ExpansionCoord;
  InnerRadius := Arc.Radius - HalfWidth - ExpansionCoord;

  if InnerRadius <= 0 then
  begin
    ShowMessage(
      'Warning: Expansion value is too large — the inner arc radius would be' + #13#10 +
      'zero or negative.  Please use a smaller expansion.');
    Exit;
  end;

  StartRad := Arc.StartAngle * Pi / 180.0;
  EndRad   := Arc.EndAngle   * Pi / 180.0;

  OStartX := Round(Arc.XCenter + OuterRadius * Cos(StartRad));
  OStartY := Round(Arc.YCenter + OuterRadius * Sin(StartRad));
  OEndX   := Round(Arc.XCenter + OuterRadius * Cos(EndRad));
  OEndY   := Round(Arc.YCenter + OuterRadius * Sin(EndRad));

  IStartX := Round(Arc.XCenter + InnerRadius * Cos(StartRad));
  IStartY := Round(Arc.YCenter + InnerRadius * Sin(StartRad));
  IEndX   := Round(Arc.XCenter + InnerRadius * Cos(EndRad));
  IEndY   := Round(Arc.YCenter + InnerRadius * Sin(EndRad));

  { --- Step 1: create helper primitives --- }
  PCBServer.PreProcess;
  OuterArcHelper := MakeHelperArc(Board, TargetLayer,
                      Arc.XCenter, Arc.YCenter, OuterRadius,
                      Arc.StartAngle, Arc.EndAngle, MilsToCoord(0.5));
  InnerArcHelper := MakeHelperArc(Board, TargetLayer,
                      Arc.XCenter, Arc.YCenter, InnerRadius,
                      Arc.StartAngle, Arc.EndAngle, MilsToCoord(0.5));
  StartLine := MakeHelperTrack(Board, TargetLayer,
                 OStartX, OStartY, IStartX, IStartY, MilsToCoord(1));
  EndLine   := MakeHelperTrack(Board, TargetLayer,
                 OEndX,   OEndY,   IEndX,   IEndY,   MilsToCoord(1));
  PCBServer.PostProcess;
  Board.ViewManager_FullUpdate;

  { --- Step 2: select only the four helpers --- }
  ResetParameters;
  RunProcess('PCB:DeselAll');
  OuterArcHelper.Selected := True;
  InnerArcHelper.Selected := True;
  StartLine.Selected      := True;
  EndLine.Selected        := True;
  Board.ViewManager_FullUpdate;

  { --- Step 3: convert to region (RunProcess manages its own transaction) --- }
  ResetParameters;
  RunProcess('PCB:CreateRegionFromSelectedPrimitives');
  Board.ViewManager_FullUpdate;

  { --- Step 4: find the new region (left selected by RunProcess) --- }
  NewRegion := FindNewRegion(Board, TargetLayer);

  if NewRegion = Nil then
    ShowMessage(
      'Warning: Region conversion may have failed — no new region was found' + #13#10 +
      'on the solder mask layer.  The helper primitives have been left in' + #13#10 +
      'place so you can inspect the state of the board.')
  else
  begin
    { --- Step 5: set Arc Approximation to 0.001 mil for smooth rendering --- }
    PCBServer.PreProcess;
    NewRegion.ArcApproximation := MilsToCoord(0.001);
    PCBServer.SendMessageToRobots(
      Board.I_ObjectAddress, c_Broadcast,
      PCBM_BoardRegisteration, NewRegion.I_ObjectAddress);
    PCBServer.PostProcess;
  end;

  { --- Step 6: delete helpers (only if conversion succeeded) --- }
  if NewRegion <> Nil then
  begin
    PCBServer.PreProcess;
    Board.RemovePCBObject(OuterArcHelper);
    Board.RemovePCBObject(InnerArcHelper);
    Board.RemovePCBObject(StartLine);
    Board.RemovePCBObject(EndLine);
    PCBServer.PostProcess;
    Board.ViewManager_FullUpdate;
  end;
end;


{ ===========================================================================
  DrawSolderMaskRegion  –  SCRIPT ENTRY POINT
  =========================================================================== }
procedure DrawSolderMaskRegion;
var
  Board       : IPCB_Board;
  Track       : IPCB_Track;
  Arc         : IPCB_Arc;
  TargetLayer : TLayer;
  SourceLayer : TLayer;
  Expansion   : Double;
  LeftOffset  : Double;
  RightOffset : Double;
  Cancelled   : Boolean;
begin
  { 1. Obtain active PCB document }
  Board := PCBServer.GetCurrentPCBBoard;
  if Board = Nil then
  begin
    ShowMessage('Error: No PCB document is currently active.' + #13#10 +
                'Please open a PCB file before running this script.');
    Exit;
  end;

  { 2. Locate and validate the selected track or arc }
  Track := Nil;
  Arc   := Nil;
  if not GetSelectedObject(Board, Track, Arc) then Exit;

  { 3. Resolve source and target layers }
  if Track <> Nil then SourceLayer := Track.Layer
  else               SourceLayer := Arc.Layer;

  if SourceLayer = eTopLayer then TargetLayer := eTopSolder
  else                            TargetLayer := eBottomSolder;

  { 4. Collect parameters from the user }
  ShowParamDialog(Expansion, LeftOffset, RightOffset, Cancelled);
  if Cancelled then Exit;

  { 5. Run the appropriate flow }
  if Track <> Nil then
    DrawTrackHelpers(Board, Track, TargetLayer, Expansion, LeftOffset, RightOffset)
  else
    DrawArcHelpers(Board, Arc, TargetLayer, MilsToCoord(Expansion));

  { 6. Final board refresh }
  Board.ViewManager_FullUpdate;

  ShowMessage(
    'Solder mask region placed successfully.' + #13#10 +
    'Layer: ' + Board.LayerName(TargetLayer));
end;
