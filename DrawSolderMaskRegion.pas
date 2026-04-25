{ ===========================================================================
  DrawSolderMaskRegion.pas
  Altium Designer 26.x  –  DelphiScript

  PURPOSE
  -------
  Places helper primitives on the solder mask layer outlining the intended
  solder mask opening for a selected copper track or arc.  No region
  conversion is attempted — the helpers are left in place for manual
  inspection or conversion.

  TRACK CASE
  ----------
  Four track segments (1 mil wide) are placed on the solder mask layer
  connecting the four corners of a rotated rectangle aligned to the track.

  ARC CASE
  --------
  Two concentric arcs (0.5 mil wide) share the copper arc's centre, start
  angle, and end angle.  Their radii are:
    Outer: CopperRadius + CopperLineWidth/2 + Expansion
    Inner: CopperRadius - CopperLineWidth/2 - Expansion
  Two straight track segments (1 mil wide) close the shape at each end.

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
  MakeHelperTrack
  Creates a track segment on TargetLayer, registers it with the board, and
  returns the object reference.  Must be called inside PreProcess/PostProcess.
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
  Creates an arc on TargetLayer, registers it with the board, and returns
  the object reference.  Angles in degrees (CCW from positive X axis).
  Must be called inside PreProcess/PostProcess.
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
  Finds exactly one selected track or arc on the Top or Bottom copper layer.
  Returns True and sets either Track or Arc (the other is left Nil).
  Displays an error and returns False if the selection is invalid.
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
  Collects Expansion, Left Offset, and Right Offset from the user (mils).
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
  DrawTrackHelpers
  Computes the four rotated rectangle corners for a track and places four
  helper track segments on TargetLayer connecting them (A→B→C→D→A).

  All track properties are converted to mils via CoordToMils at the top.
  Geometry is computed in mils as Double.  Corners are converted back to
  TCoord via MilsToCoord only at the final MakeHelperTrack call.

  deltaX / deltaY name the along-track direction vector.  These do not
  collide with the corner variables ax/ay … dx/dy in DelphiScript's
  case-insensitive environment because "deltaX" ≠ "dx".
  --------------------------------------------------------------------------- }
procedure DrawTrackHelpers(Board       : IPCB_Board;
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
  LineW           : TCoord;
begin
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

  LineW := MilsToCoord(1);

  PCBServer.PreProcess;
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(ax), MilsToCoord(ay), MilsToCoord(bx), MilsToCoord(by), LineW);
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(bx), MilsToCoord(by), MilsToCoord(cx), MilsToCoord(cy), LineW);
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(cx), MilsToCoord(cy), MilsToCoord(dx), MilsToCoord(dy), LineW);
  MakeHelperTrack(Board, TargetLayer,
    MilsToCoord(dx), MilsToCoord(dy), MilsToCoord(ax), MilsToCoord(ay), LineW);
  PCBServer.PostProcess;
end;


{ ---------------------------------------------------------------------------
  DrawArcHelpers
  Places two concentric arcs and two closing track segments on TargetLayer
  outlining the solder mask opening for a copper arc.

  Outer arc radius = CopperRadius + CopperLineWidth/2 + Expansion
  Inner arc radius = CopperRadius - CopperLineWidth/2 - Expansion
  Both arcs share the copper arc's centre, start angle, and end angle.
  Closing tracks connect the outer and inner arc endpoints at each end.
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

  PCBServer.PreProcess;
  MakeHelperArc(Board, TargetLayer,
    Arc.XCenter, Arc.YCenter, OuterRadius,
    Arc.StartAngle, Arc.EndAngle, MilsToCoord(0.5));
  MakeHelperArc(Board, TargetLayer,
    Arc.XCenter, Arc.YCenter, InnerRadius,
    Arc.StartAngle, Arc.EndAngle, MilsToCoord(0.5));
  MakeHelperTrack(Board, TargetLayer,
    OStartX, OStartY, IStartX, IStartY, MilsToCoord(1));
  MakeHelperTrack(Board, TargetLayer,
    OEndX, OEndY, IEndX, IEndY, MilsToCoord(1));
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
    DrawTrackHelpers(Board, Track, TargetLayer, Expansion, LeftOffset, RightOffset)
  else
    DrawArcHelpers(Board, Arc, TargetLayer, MilsToCoord(Expansion));

  Board.ViewManager_FullUpdate;

  ShowMessage(
    'Helper primitives placed on: ' + Board.LayerName(TargetLayer));
end;
