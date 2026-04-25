{ ===========================================================================
  DrawSolderMaskRegion.pas
  Altium Designer 26.x  –  DelphiScript

  PURPOSE
  -------
  Places helper primitives on the solder mask layer that outline the
  intended solder mask opening for a selected copper track or arc.

  This is an INTERMEDIATE / VERIFICATION version.  The helpers are left
  in place so the geometry can be inspected before the conversion-and-
  cleanup step is added.

  TRACK CASE
  ----------
  Four track segments are drawn on the solder mask layer connecting the
  four corners of the rotated rectangle (A→B top, B→C right, C→D bottom,
  D→A left).  Width: 1 mil.

  ARC CASE
  --------
  Two arcs are drawn concentric with the copper arc:
    Outer arc radius = CopperRadius + CopperLineWidth/2 + Expansion
    Inner arc radius = CopperRadius − CopperLineWidth/2 − Expansion
  Both share the copper arc's centre, start angle, and end angle.
  Two straight track segments connect the endpoint pairs:
    Start-angle line: outer start point → inner start point
    End-angle line:   outer end point   → inner end point
  Arc helper width: 0.5 mil.  Track helper width: 1 mil.

  NOTE: Left/Right offsets apply to tracks only.  They are ignored for arcs.

  PRE-CONDITIONS
  --------------
  Exactly one track OR one arc must be selected on the Top or Bottom copper
  layer before running the script.

  DIALOG PARAMETERS  (mils)
  -------------------------
  Expansion    – distance beyond the physical edge of the copper primitive
  Left Offset  – inset of the left/start short edge (tracks only)
  Right Offset – inset of the right/end short edge (tracks only)

  LEFT / RIGHT ENDPOINT CONVENTION
  ---------------------------------
  For non-vertical tracks:
    "Left"  = endpoint with the more-negative X coordinate.
  For exactly vertical tracks (X1 = X2):
    "Left"  = endpoint with the more-negative Y coordinate (i.e. the
              bottom endpoint in Altium's upward-Y coordinate system).
    "Right" = the top endpoint.
  The Left/Right Offset values inset the corresponding short edge of the
  rectangle inward (toward the centre of the track).

  =========================================================================== }


{ ---------------------------------------------------------------------------
  MakeHelperTrack
  Creates a track segment on TargetLayer, registers it with the board, and
  returns the object reference.  Width is in Altium internal units (TCoord).
  Must be called inside a PreProcess / PostProcess block.
  --------------------------------------------------------------------------- }
function MakeHelperTrack(Board       : IPCB_Board;
                         TargetLayer : TLayer;
                         X1, Y1      : TCoord;
                         X2, Y2      : TCoord;
                         LineWidth   : TCoord) : IPCB_Track;
var
  T : IPCB_Track;
begin
  T           := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
  T.X1        := X1;
  T.Y1        := Y1;
  T.X2        := X2;
  T.Y2        := Y2;
  T.Layer     := TargetLayer;
  T.LineWidth := LineWidth;

  Board.AddPCBObject(T);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, T.I_ObjectAddress
  );

  Result := T;
end;


{ ---------------------------------------------------------------------------
  MakeHelperArc
  Creates an arc on TargetLayer, registers it with the board, and returns
  the object reference.  All coordinates/radius in Altium internal units;
  angles in degrees (CCW from positive X axis, Altium convention).
  Must be called inside a PreProcess / PostProcess block.
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
  A             := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
  A.XCenter     := CX;
  A.YCenter     := CY;
  A.Radius      := ArcRadius;
  A.StartAngle  := StartAngleDeg;
  A.EndAngle    := EndAngleDeg;
  A.Layer       := TargetLayer;
  A.LineWidth   := LineWidth;

  Board.AddPCBObject(A);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, A.I_ObjectAddress
  );

  Result := A;
end;


{ ---------------------------------------------------------------------------
  GetSelectedObject
  Searches the board for a single selected track or arc on the Top or Bottom
  copper layer.

  On success returns True and sets either Track (leaving Arc = Nil) or
  Arc (leaving Track = Nil).  On failure shows an error and returns False.
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

  { --- scan tracks --- }
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

  { --- scan arcs --- }
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

  { --- validate --- }
  if SelCount = 0 then
  begin
    ShowMessage(
      'Error: No qualifying object selected.' + #13#10 + #13#10 +
      'Please select exactly one track or arc on the Top or' + #13#10 +
      'Bottom copper layer, then re-run the script.'
    );
    Exit;
  end;

  if SelCount > 1 then
  begin
    ShowMessage(
      'Error: Multiple objects are selected (' + IntToStr(SelCount) + ').' + #13#10 + #13#10 +
      'Please select exactly one track or arc and re-run the script.'
    );
    Exit;
  end;

  { If both got set somehow (shouldn't happen), prefer track and clear arc }
  if (Track <> Nil) and (Arc <> Nil) then
    Arc := Nil;

  Result := True;
end;


{ ---------------------------------------------------------------------------
  ShowParamDialog
  Collects Expansion, Left Offset, and Right Offset from the user (mils).
  Left/Right offsets are labelled as track-only in the UI.
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
        ValidationOK := False;
        Continue;
      end;
      Expansion := ParsedVal;

      ParsedVal := StrToFloatDef(EdtLeft.Text, -1);
      if ParsedVal < 0 then
      begin
        ShowMessage('Left offset must be a non-negative number.');
        ValidationOK := False;
        Continue;
      end;
      LeftOffset := ParsedVal;

      ParsedVal := StrToFloatDef(EdtRight.Text, -1);
      if ParsedVal < 0 then
      begin
        ShowMessage('Right offset must be a non-negative number.');
        ValidationOK := False;
        Continue;
      end;
      RightOffset := ParsedVal;
    end;

    Cancelled := False;
  finally
    Dlg.Free;
  end;
end;


{ ---------------------------------------------------------------------------
  DrawTrackHelpers
  Computes the four rotated rectangle corners for a track and places four
  helper track segments on TargetLayer connecting them (A→B→C→D→A).

  UNIT STRATEGY
  -------------
  All track properties (X1, Y1, X2, Y2, LineWidth) are converted to mils
  via CoordToMils at the start.  Expansion, LeftOffset, RightOffset are
  already in mils from the dialog.  All geometry is computed in mils as
  Double.  Only at the final step are coordinates converted back to TCoord
  via MilsToCoord for the MakeHelperTrack calls.  This avoids any risk of
  unit mismatch between TCoord properties and MilsToCoord/CoordToMils.

  GEOMETRY
  --------
  u    = unit vector along track (left endpoint → right endpoint)
  v    = unit vector 90° CCW from u
  half = LineWidth/2 + Expansion                              (mils)
  A (top-left)     = P_L + Lo·u + half·v
  B (top-right)    = P_R − Ro·u + half·v
  C (bottom-right) = P_R − Ro·u − half·v
  D (bottom-left)  = P_L + Lo·u − half·v

  LEFT / RIGHT ASSIGNMENT
  -----------------------
  Left  = endpoint with more-negative X.
  Tiebreaker for exactly vertical tracks (X1 = X2):
    Left  = endpoint with more-negative Y (= bottom in Altium's upward-Y system)
    Right = endpoint with more-positive Y (= top)
  --------------------------------------------------------------------------- }
procedure DrawTrackHelpers(Board       : IPCB_Board;
                           Track       : IPCB_Track;
                           TargetLayer : TLayer;
                           Expansion   : Double;    { mils }
                           LeftOffset  : Double;    { mils }
                           RightOffset : Double);   { mils }
var
  Lx, Ly       : Double;   { left  endpoint, mils }
  Rx, Ry       : Double;   { right endpoint, mils }
  dRawX, dRawY : Double;
  TraceLen     : Double;
  ux, uy       : Double;   { unit vector along track }
  vx, vy       : Double;   { unit vector perpendicular (90° CCW) }
  Half, Lo, Ro : Double;   { mils }
  ax, ay       : Double;   { corner A, mils }
  bx, by       : Double;   { corner B, mils }
  cx, cy       : Double;   { corner C, mils }
  dx, dy       : Double;   { corner D, mils }
  LineW        : TCoord;
begin
  { --- Assign left/right endpoints (all values converted to mils) ---
    Non-vertical: left = more-negative X.
    Vertical (X1=X2): left = more-negative Y (bottom). }
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

  dRawX    := Rx - Lx;
  dRawY    := Ry - Ly;
  TraceLen := Sqrt(dRawX * dRawX + dRawY * dRawY);

  if TraceLen < 0.001 then   { guard against zero-length track }
  begin
    ShowMessage('Warning: The selected track has zero (or near-zero) length. Skipped.');
    Exit;
  end;

  ux := dRawX / TraceLen;
  uy := dRawY / TraceLen;
  vx := -uy;
  vy :=  ux;

  { Half-width in mils: LineWidth/2 + Expansion }
  Half := CoordToMils(Track.LineWidth) / 2.0 + Expansion;
  Lo   := LeftOffset;
  Ro   := RightOffset;

  { Compute corners in mils }
  ax := Lx + Lo * ux + Half * vx;   { A: top-left     }
  ay := Ly + Lo * uy + Half * vy;
  bx := Rx - Ro * ux + Half * vx;   { B: top-right    }
  by := Ry - Ro * uy + Half * vy;
  cx := Rx - Ro * ux - Half * vx;   { C: bottom-right }
  cy := Ry - Ro * uy - Half * vy;
  dx := Lx + Lo * ux - Half * vx;   { D: bottom-left  }
  dy := Ly + Lo * uy - Half * vy;

  { Place helper tracks (convert corners back to TCoord at this final step) }
  LineW := MilsToCoord(1);
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(ax), MilsToCoord(ay), MilsToCoord(bx), MilsToCoord(by), LineW);
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(bx), MilsToCoord(by), MilsToCoord(cx), MilsToCoord(cy), LineW);
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(cx), MilsToCoord(cy), MilsToCoord(dx), MilsToCoord(dy), LineW);
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(dx), MilsToCoord(dy), MilsToCoord(ax), MilsToCoord(ay), LineW);
end;


{ ---------------------------------------------------------------------------
  DrawArcHelpers
  Places the four helper primitives that outline the solder mask opening for
  a copper arc:
    - Outer helper arc: same centre/angles, radius = ArcRadius + half-width + Expansion
    - Inner helper arc: same centre/angles, radius = ArcRadius − half-width − Expansion
    - Start-angle line: outer start point → inner start point
    - End-angle   line: outer end point   → inner end point

  All arc helper widths are 0.5 mil; connecting line widths are 1 mil.
  Angles are in degrees (Altium convention, CCW from positive X axis).
  ExpansionCoord must be in Altium internal units (TCoord).
  --------------------------------------------------------------------------- }
procedure DrawArcHelpers(Board          : IPCB_Board;
                         Arc            : IPCB_Arc;
                         TargetLayer    : TLayer;
                         ExpansionCoord : TCoord);
var
  HalfWidth    : TCoord;
  OuterRadius  : TCoord;
  InnerRadius  : TCoord;
  StartRad     : Double;
  EndRad       : Double;
  OStartX, OStartY : TCoord;
  OEndX,   OEndY   : TCoord;
  IStartX, IStartY : TCoord;
  IEndX,   IEndY   : TCoord;
begin
  HalfWidth   := Arc.LineWidth div 2;
  OuterRadius := Arc.Radius + HalfWidth + ExpansionCoord;
  InnerRadius := Arc.Radius - HalfWidth - ExpansionCoord;

  if InnerRadius <= 0 then
  begin
    ShowMessage(
      'Warning: The expansion value is too large — the inner helper arc' + #13#10 +
      'radius would be zero or negative.  Please use a smaller expansion.'
    );
    Exit;
  end;

  MakeHelperArc(Board, TargetLayer,
                Arc.XCenter, Arc.YCenter,
                OuterRadius,
                Arc.StartAngle, Arc.EndAngle,
                MilsToCoord(0.5));

  MakeHelperArc(Board, TargetLayer,
                Arc.XCenter, Arc.YCenter,
                InnerRadius,
                Arc.StartAngle, Arc.EndAngle,
                MilsToCoord(0.5));

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

  MakeHelperTrack(Board, TargetLayer, OStartX, OStartY, IStartX, IStartY, MilsToCoord(1));
  MakeHelperTrack(Board, TargetLayer, OEndX,   OEndY,   IEndX,   IEndY,   MilsToCoord(1));
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
  if Track <> Nil then
    SourceLayer := Track.Layer
  else
    SourceLayer := Arc.Layer;

  if SourceLayer = eTopLayer then
    TargetLayer := eTopSolder
  else
    TargetLayer := eBottomSolder;

  { 4. Collect parameters from the user }
  ShowParamDialog(Expansion, LeftOffset, RightOffset, Cancelled);
  if Cancelled then Exit;

  { 5. Draw helper primitives (undo-safe transaction) }
  PCBServer.PreProcess;
  try
    if Track <> Nil then
      { Expansion, LeftOffset, RightOffset passed in mils — DrawTrackHelpers
        handles all unit conversion internally via CoordToMils / MilsToCoord. }
      DrawTrackHelpers(Board, Track, TargetLayer, Expansion, LeftOffset, RightOffset)
    else
      DrawArcHelpers(Board, Arc, TargetLayer, MilsToCoord(Expansion));
  finally
    PCBServer.PostProcess;
  end;

  { 6. Refresh the board view }
  Board.ViewManager_FullUpdate;

  ShowMessage(
    'Helper primitives placed on: ' + Board.LayerName(TargetLayer) + #13#10 +
    'Please verify the geometry, then report back to proceed' + #13#10 +
    'with region conversion and cleanup.'
  );
end;
