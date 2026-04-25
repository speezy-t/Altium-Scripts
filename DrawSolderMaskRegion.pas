{ ===========================================================================
  DrawSolderMaskRegion.pas
  Altium Designer 26.x  –  DelphiScript

  PURPOSE
  -------
  Places a filled solder-mask opening region aligned to a selected copper
  track or arc on the Top or Bottom signal layer.

  REGION CREATION STRATEGY
  ------------------------
  Regions are created directly via the PCB object factory and populated by
  calling AddPoint on the region's MainContour property.  No helper
  primitives or RunProcess conversion are used.

  TRACK CASE
  ----------
  The region outline is a rotated rectangle defined by four corner points
  computed from the track geometry (width, expansion, left/right offsets).

  ARC CASE
  --------
  The region outline is a polygon that approximates the arc-bounded shape.
  Points are computed at 1-degree intervals along both the outer arc
  (radius = CopperRadius + halfWidth + Expansion) and inner arc
  (radius = CopperRadius - halfWidth - Expansion), then connected at the
  start and end angles to form a closed loop.  At 1-degree resolution the
  result is visually indistinguishable from a perfect arc.

  NOTE ON PROPERTY NAME
  ---------------------
  If "undeclared identifier: MainContour" is reported, the contour property
  has a different name in your build.  Candidates to try in order:
    Region.Outline         (pre-v20 name — was undeclared in our testing)
    Region.MainContour     (current attempt)
    Region.GeometricPolygon
  Replace every occurrence of .MainContour below with the next candidate.

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

  =========================================================================== }


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
  PlaceTrackRegion
  Creates a rectangular region directly on TargetLayer using the four
  pre-computed corner coordinates (in mils).  All geometry is converted to
  TCoord at the point of the AddPoint call.

  The region outline is populated via Region.MainContour.AddPoint.
  If "undeclared identifier: MainContour" is reported, replace every
  occurrence of .MainContour with the correct property name for your build
  (see the NOTE ON PROPERTY NAME in the file header).
  --------------------------------------------------------------------------- }
procedure PlaceTrackRegion(Board       : IPCB_Board;
                           TargetLayer : TLayer;
                           ax, ay      : Double;
                           bx, by      : Double;
                           cx, cy      : Double;
                           dx, dy      : Double);
var
  Region : IPCB_Region;
begin
  Region := PCBServer.PCBObjectFactory(eRegionObject, eNoDimension, eCreate_Default);
  if Region = Nil then
  begin
    ShowMessage('Error: Could not create Region object.');
    Exit;
  end;

  Region.Layer := TargetLayer;

  Region.MainContour.AddPoint(MilsToCoord(ax), MilsToCoord(ay));
  Region.MainContour.AddPoint(MilsToCoord(bx), MilsToCoord(by));
  Region.MainContour.AddPoint(MilsToCoord(cx), MilsToCoord(cy));
  Region.MainContour.AddPoint(MilsToCoord(dx), MilsToCoord(dy));

  Board.AddPCBObject(Region);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Region.I_ObjectAddress);
end;


{ ---------------------------------------------------------------------------
  PlaceArcRegion
  Creates a region directly on TargetLayer whose outline approximates the
  arc-bounded shape using a polygon at 1-degree resolution.

  The polygon is built as follows (viewed from outside the arc):
    - Outer arc: points from StartAngle to EndAngle at OuterRadius
    - Inner arc: points from EndAngle back to StartAngle at InnerRadius
  These two sequences share their first and last points, so the polygon
  closes naturally.

  SWEEP ANGLE
  -----------
  Altium arcs run counterclockwise from StartAngle to EndAngle.
  If EndAngle <= StartAngle the arc wraps through 0° and the actual
  counterclockwise sweep = EndAngle - StartAngle + 360.
  --------------------------------------------------------------------------- }
procedure PlaceArcRegion(Board          : IPCB_Board;
                         Arc            : IPCB_Arc;
                         TargetLayer    : TLayer;
                         ExpansionCoord : TCoord);
var
  HalfWidth    : TCoord;
  OuterRadius  : TCoord;
  InnerRadius  : TCoord;
  SweepDeg     : Double;
  NumSteps     : Integer;
  StepDeg      : Double;
  AngleDeg     : Double;
  AngleRad     : Double;
  px, py       : TCoord;
  i            : Integer;
  Region       : IPCB_Region;
begin
  HalfWidth   := Arc.LineWidth div 2;
  OuterRadius := Arc.Radius + HalfWidth + ExpansionCoord;
  InnerRadius := Arc.Radius - HalfWidth - ExpansionCoord;

  if InnerRadius <= 0 then
  begin
    ShowMessage(
      'Warning: Expansion value is too large — inner arc radius would be' + #13#10 +
      'zero or negative.  Please use a smaller expansion.');
    Exit;
  end;

  { Compute the counterclockwise sweep in degrees }
  SweepDeg := Arc.EndAngle - Arc.StartAngle;
  if SweepDeg <= 0 then SweepDeg := SweepDeg + 360;

  { One step per degree; minimum of 4 steps for very short arcs }
  NumSteps := Round(SweepDeg);
  if NumSteps < 4 then NumSteps := 4;
  StepDeg := SweepDeg / NumSteps;

  Region := PCBServer.PCBObjectFactory(eRegionObject, eNoDimension, eCreate_Default);
  if Region = Nil then
  begin
    ShowMessage('Error: Could not create Region object.');
    Exit;
  end;

  Region.Layer := TargetLayer;

  { Outer arc: StartAngle → EndAngle (counterclockwise) }
  for i := 0 to NumSteps do
  begin
    AngleDeg := Arc.StartAngle + i * StepDeg;
    AngleRad := AngleDeg * Pi / 180.0;
    px := Round(Arc.XCenter + OuterRadius * Cos(AngleRad));
    py := Round(Arc.YCenter + OuterRadius * Sin(AngleRad));
    Region.MainContour.AddPoint(px, py);
  end;

  { Inner arc: EndAngle → StartAngle (clockwise — reverse iteration) }
  for i := NumSteps downto 0 do
  begin
    AngleDeg := Arc.StartAngle + i * StepDeg;
    AngleRad := AngleDeg * Pi / 180.0;
    px := Round(Arc.XCenter + InnerRadius * Cos(AngleRad));
    py := Round(Arc.YCenter + InnerRadius * Sin(AngleRad));
    Region.MainContour.AddPoint(px, py);
  end;

  Board.AddPCBObject(Region);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Region.I_ObjectAddress);
end;


{ ---------------------------------------------------------------------------
  DrawTrackRegion
  Computes the rotated rectangle corners for a track and calls PlaceTrackRegion.
  All geometry is done in mils (Double); TCoord conversion happens inside
  PlaceTrackRegion at the AddPoint call.

  deltaX / deltaY name the along-track direction vector components.
  These are distinct from the corner variables ax/ay … dx/dy even in
  DelphiScript's case-insensitive environment because "deltaX" ≠ "dx".
  --------------------------------------------------------------------------- }
procedure DrawTrackRegion(Board       : IPCB_Board;
                          Track       : IPCB_Track;
                          TargetLayer : TLayer;
                          Expansion   : Double;
                          LeftOffset  : Double;
                          RightOffset : Double);
var
  Lx, Ly, Rx, Ry  : Double;
  deltaX, deltaY  : Double;
  TrackAngle      : Double;
  ux, uy, vx, vy : Double;
  Half, Lo, Ro    : Double;
  ax, ay          : Double;
  bx, by          : Double;
  cx, cy          : Double;
  dx, dy          : Double;
begin
  { Assign left/right endpoints (mils).
    Left = more-negative X; tiebreaker for vertical tracks: lower Y = left. }
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

  deltaX := Rx - Lx;
  deltaY := Ry - Ly;

  if (Abs(deltaX) < 0.001) and (Abs(deltaY) < 0.001) then
  begin
    ShowMessage('Warning: The selected track has zero (or near-zero) length. Skipped.');
    Exit;
  end;

  TrackAngle := ArcTan2(deltaY, deltaX);
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

  PCBServer.PreProcess;
  PlaceTrackRegion(Board, TargetLayer, ax, ay, bx, by, cx, cy, dx, dy);
  PCBServer.PostProcess;
end;


{ ---------------------------------------------------------------------------
  DrawArcRegion
  Calls PlaceArcRegion inside a PreProcess/PostProcess transaction.
  --------------------------------------------------------------------------- }
procedure DrawArcRegion(Board          : IPCB_Board;
                        Arc            : IPCB_Arc;
                        TargetLayer    : TLayer;
                        ExpansionCoord : TCoord);
begin
  PCBServer.PreProcess;
  PlaceArcRegion(Board, Arc, TargetLayer, ExpansionCoord);
  PCBServer.PostProcess;
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
  Board := PCBServer.GetCurrentPCBBoard;
  if Board = Nil then
  begin
    ShowMessage('Error: No PCB document is currently active.' + #13#10 +
                'Please open a PCB file before running this script.');
    Exit;
  end;

  Track := Nil;
  Arc   := Nil;
  if not GetSelectedObject(Board, Track, Arc) then Exit;

  if Track <> Nil then SourceLayer := Track.Layer
  else               SourceLayer := Arc.Layer;

  if SourceLayer = eTopLayer then TargetLayer := eTopSolder
  else                            TargetLayer := eBottomSolder;

  ShowParamDialog(Expansion, LeftOffset, RightOffset, Cancelled);
  if Cancelled then Exit;

  if Track <> Nil then
    DrawTrackRegion(Board, Track, TargetLayer, Expansion, LeftOffset, RightOffset)
  else
    DrawArcRegion(Board, Arc, TargetLayer, MilsToCoord(Expansion));

  Board.ViewManager_FullUpdate;

  ShowMessage(
    'Solder mask region placed successfully.' + #13#10 +
    'Layer: ' + Board.LayerName(TargetLayer));
end;
