// ============================================================================
// ViaStitchTemplate.pas
// Altium Designer DelphiScript
//
// Places via stitch marker circles on mechanical layer M100
// ("Via Stitch Template") for a selected track segment or arc segment.
//
// Each marker is a full 360-degree arc (circle) with:
//   - Radius    = via_diameter / 2
//   - LineWidth = 2 mils
//
// Two staggered rows of markers are placed on each side of the trace/arc:
//   Inner row : offset = InnerRowOffset from trace/arc centre
//   Outer row : offset = OuterRowOffset from trace/arc centre,
//               staggered by half the inner-row pitch
//
// All user inputs and internal calculations are in mils.
// ============================================================================


// ============================================================================
//  MATH HELPER
// ============================================================================

// ArcSin implementation in case the Math unit is not in scope.
function SafeArcSin(X : Double) : Double;
begin
  if      X >=  1.0 then Result :=  Pi / 2.0
  else if X <= -1.0 then Result := -Pi / 2.0
  else                   Result :=  ArcTan(X / Sqrt(1.0 - X * X));
end;


// ============================================================================
//  DIALOG
// ============================================================================

// Global edit-box references so the OK handler can read them.
Var
  GEdtDiameter    : TEdit;
  GEdtInnerOffset : TEdit;
  GEdtOuterOffset : TEdit;

procedure OnOKClick(Sender : TObject);
begin
  TForm(TButton(Sender).Owner).ModalResult := mrOK;
end;

procedure OnCancelClick(Sender : TObject);
begin
  TForm(TButton(Sender).Owner).ModalResult := mrCancel;
end;

// Shows the parameter dialog. Returns True if the user clicked OK.
// DiamMils, InnerOffMils, OuterOffMils are set on return.
function ShowParamDialog(Var DiamMils, InnerOffMils, OuterOffMils : Double) : Boolean;
Var
  Frm : TForm;
  Lbl : TLabel;
  Btn : TButton;
begin
  Frm := TForm.Create(nil);
  try
    Frm.Caption     := 'Via Stitch Template Parameters';
    Frm.Width       := 310;
    Frm.Height      := 210;
    Frm.Position    := poScreenCenter;
    Frm.BorderStyle := bsDialog;

    // --- Via Diameter ---
    Lbl         := TLabel.Create(Frm); Lbl.Parent := Frm;
    Lbl.Caption := 'Via Diameter (mils):';
    Lbl.Left    := 12;  Lbl.Top := 18;

    GEdtDiameter        := TEdit.Create(Frm); GEdtDiameter.Parent := Frm;
    GEdtDiameter.Left   := 185; GEdtDiameter.Top   := 14;
    GEdtDiameter.Width  := 90;  GEdtDiameter.Text  := '20';

    // --- Inner Row Offset ---
    Lbl         := TLabel.Create(Frm); Lbl.Parent := Frm;
    Lbl.Caption := 'Inner Row Offset (mils):';
    Lbl.Left    := 12;  Lbl.Top := 54;

    GEdtInnerOffset        := TEdit.Create(Frm); GEdtInnerOffset.Parent := Frm;
    GEdtInnerOffset.Left   := 185; GEdtInnerOffset.Top   := 50;
    GEdtInnerOffset.Width  := 90;  GEdtInnerOffset.Text  := '50';

    // --- Outer Row Offset ---
    Lbl         := TLabel.Create(Frm); Lbl.Parent := Frm;
    Lbl.Caption := 'Outer Row Offset (mils):';
    Lbl.Left    := 12;  Lbl.Top := 90;

    GEdtOuterOffset        := TEdit.Create(Frm); GEdtOuterOffset.Parent := Frm;
    GEdtOuterOffset.Left   := 185; GEdtOuterOffset.Top   := 86;
    GEdtOuterOffset.Width  := 90;  GEdtOuterOffset.Text  := '80';

    // --- Buttons ---
    Btn           := TButton.Create(Frm); Btn.Parent := Frm;
    Btn.Caption   := 'OK';
    Btn.Left      := 124; Btn.Top := 136; Btn.Width := 76;
    Btn.Default   := True;
    Btn.OnClick   := OnOKClick;

    Btn           := TButton.Create(Frm); Btn.Parent := Frm;
    Btn.Caption   := 'Cancel';
    Btn.Left      := 208; Btn.Top := 136; Btn.Width := 76;
    Btn.OnClick   := OnCancelClick;

    if Frm.ShowModal = mrOK then
    begin
      DiamMils     := StrToFloatDef(GEdtDiameter.Text,    20.0);
      InnerOffMils := StrToFloatDef(GEdtInnerOffset.Text, 50.0);
      OuterOffMils := StrToFloatDef(GEdtOuterOffset.Text, 80.0);
      Result := True;
    end
    else
      Result := False;
  finally
    Frm.Free;
  end;
end;


// ============================================================================
//  LAYER MANAGEMENT
// ============================================================================

// Returns the TLayer for M100, creating/naming it "Via Stitch Template"
// if it does not already exist or has no name.
function EnsureViaStitchLayer(Board : IPCB_Board) : TLayer;
Var
  Layer    : TLayer;
  LayerObj : IPCB_LayerObject;
begin
  Layer    := LayerUtils.MechanicalLayer(100);
  LayerObj := Board.LayerStack.LayerObject[Layer];

  if Assigned(LayerObj) then
  begin
    if LayerObj.Name = '' then
      LayerObj.Name := 'Via Stitch Template'
    else if LayerObj.Name <> 'Via Stitch Template' then
      ShowMessage('Note: M100 is already named "' + LayerObj.Name + '". ' +
                  'Via markers will be placed on this layer regardless.');
  end
  else
  begin
    // Layer object not accessible through the stack API — warn but continue.
    // In some Altium versions you may need to manually enable M100 in
    // the Layer Stack Manager before running this script.
    ShowMessage('Warning: M100 could not be confirmed in the layer stack. ' +
                'Please ensure "Via Stitch Template" (M100) exists. ' +
                'Markers will be placed on M100 regardless.');
  end;

  Result := Layer;
end;


// ============================================================================
//  CIRCLE (VIA MARKER) PLACEMENT
// ============================================================================

// Places a full 360-degree arc (circle) on the given layer.
// CXCoord, CYCoord : centre in Altium internal coordinates (TCoord)
// RadiusMils       : radius in mils
procedure PlaceCircle(Board    : IPCB_Board;
                      Layer    : TLayer;
                      CXCoord  : TCoord;
                      CYCoord  : TCoord;
                      RadiusMils : Double);
Var
  Circ : IPCB_Arc;
begin
  Circ := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
  if not Assigned(Circ) then Exit;

  Circ.XCenter    := CXCoord;
  Circ.YCenter    := CYCoord;
  Circ.Radius     := MilsToCoord(RadiusMils);
  Circ.LineWidth  := MilsToCoord(2.0);
  Circ.StartAngle := 0.0;
  Circ.EndAngle   := 360.0;
  Circ.Layer      := Layer;

  Board.AddPCBObject(Circ);
  PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast,
                                PCBM_BoardRegistered, Circ.I_ObjectAddress);
end;


// ============================================================================
//  TRACK SEGMENT PROCESSING
// ============================================================================

procedure ProcessTrack(Board        : IPCB_Board;
                       Track        : IPCB_Track;
                       Layer        : TLayer;
                       DiamMils     : Double;
                       InnerOffMils : Double;
                       OuterOffMils : Double);
Var
  X1M, Y1M       : Double;   // track start in mils
  DXM, DYM       : Double;   // (end - start) in mils
  LenMils        : Double;   // track length in mils
  UX, UY         : Double;   // unit vector along track
  PX, PY         : Double;   // unit perpendicular (left-hand side)
  NSeg           : Integer;  // number of equal segments
  PosAlong       : Double;   // distance along track in mils
  CX, CY         : Double;   // marker centre in mils
  i              : Integer;
begin
  // Coordinates in mils
  X1M := CoordToMils(Track.X1);
  Y1M := CoordToMils(Track.Y1);
  DXM := CoordToMils(Track.X2) - X1M;
  DYM := CoordToMils(Track.Y2) - Y1M;
  LenMils := Sqrt(DXM * DXM + DYM * DYM);

  if LenMils <= DiamMils then
  begin
    ShowMessage(Format('Track length (%.2f mils) must be strictly greater than ' +
                       'the via diameter (%.2f mils).', [LenMils, DiamMils]));
    Exit;
  end;

  // Unit vectors
  UX :=  DXM / LenMils;
  UY :=  DYM / LenMils;
  PX := -UY;              // perpendicular: 90 deg CCW from track direction
  PY :=  UX;

  // Largest NSeg such that LenMils / NSeg > DiamMils
  NSeg := Trunc(LenMils / DiamMils);
  while (NSeg > 0) and (LenMils / NSeg <= DiamMils) do
    Dec(NSeg);

  if NSeg < 1 then
  begin
    ShowMessage('Cannot compute a valid segment count. Please check inputs.');
    Exit;
  end;

  // ------------------------------------------------------------------
  //  Inner row  —  NSeg + 1 markers per side
  // ------------------------------------------------------------------
  for i := 0 to NSeg do
  begin
    PosAlong := (i / NSeg) * LenMils;

    // +perpendicular side
    CX := X1M + PosAlong * UX + InnerOffMils * PX;
    CY := Y1M + PosAlong * UY + InnerOffMils * PY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);

    // -perpendicular side
    CX := X1M + PosAlong * UX - InnerOffMils * PX;
    CY := Y1M + PosAlong * UY - InnerOffMils * PY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);
  end;

  // ------------------------------------------------------------------
  //  Outer row  —  NSeg markers per side, staggered by half-pitch
  // ------------------------------------------------------------------
  for i := 0 to NSeg - 1 do
  begin
    PosAlong := ((i + 0.5) / NSeg) * LenMils;

    // +perpendicular side
    CX := X1M + PosAlong * UX + OuterOffMils * PX;
    CY := Y1M + PosAlong * UY + OuterOffMils * PY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);

    // -perpendicular side
    CX := X1M + PosAlong * UX - OuterOffMils * PX;
    CY := Y1M + PosAlong * UY - OuterOffMils * PY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);
  end;
end;


// ============================================================================
//  ARC SEGMENT PROCESSING
// ============================================================================

procedure ProcessArc(Board        : IPCB_Board;
                     ArcSeg       : IPCB_Arc;
                     Layer        : TLayer;
                     DiamMils     : Double;
                     InnerOffMils : Double;
                     OuterOffMils : Double);
Var
  CXM, CYM          : Double;   // arc centre in mils
  R                 : Double;   // arc radius in mils
  StartDeg          : Double;   // start angle (degrees, Altium CCW convention)
  TotalDeg          : Double;   // total CCW sweep in degrees
  TotalRad          : Double;   // total CCW sweep in radians
  RInner            : Double;   // R - InnerOffMils  (centre-side inner row)
  MinChordAngleRad  : Double;   // smallest theta satisfying chord > DiamMils at RInner
  NSeg              : Integer;  // number of equal angular segments
  AngleDeg          : Double;   // current angle in degrees
  AngleRad          : Double;   // current angle in radians
  VX, VY            : Double;   // unit radial vector at current angle
  CX, CY            : Double;   // marker centre in mils
  ROuter            : Double;   // R - OuterOffMils (centre-side outer row, if positive)
  i                 : Integer;
begin
  CXM      := CoordToMils(ArcSeg.XCenter);
  CYM      := CoordToMils(ArcSeg.YCenter);
  R        := CoordToMils(ArcSeg.Radius);
  StartDeg := ArcSeg.StartAngle;

  // Total CCW sweep — Altium stores EndAngle > StartAngle for CCW arcs;
  // add 360 if the difference is zero or negative (full circle edge case).
  TotalDeg := ArcSeg.EndAngle - StartDeg;
  if TotalDeg <= 0.0 then TotalDeg := TotalDeg + 360.0;
  TotalRad := TotalDeg * Pi / 180.0;

  // -----------------------------------------------------------------
  //  Determine theta (angular pitch) from the inner concentric arc
  //  at radius RInner = R - InnerOffMils, which has the shortest
  //  chord lengths and is therefore the binding constraint.
  // -----------------------------------------------------------------
  RInner := R - InnerOffMils;

  if RInner <= 0.0 then
  begin
    ShowMessage(Format('Inner row offset (%.2f mils) equals or exceeds the arc ' +
                       'radius (%.2f mils). Cannot place inner-side markers.',
                       [InnerOffMils, R]));
    Exit;
  end;

  if DiamMils >= 2.0 * RInner then
  begin
    ShowMessage(Format('Via diameter (%.2f mils) is too large for the inner arc ' +
                       'radius (%.2f mils). Chord constraint cannot be satisfied.',
                       [DiamMils, RInner]));
    Exit;
  end;

  // Minimum angular step: chord = 2·r·sin(θ/2) > DiamMils
  //   => θ > 2·arcsin(DiamMils / (2·RInner))
  MinChordAngleRad := 2.0 * SafeArcSin(DiamMils / (2.0 * RInner));

  // Largest NSeg such that TotalRad / NSeg > MinChordAngleRad
  NSeg := Trunc(TotalRad / MinChordAngleRad);
  while (NSeg > 0) and (TotalRad / NSeg <= MinChordAngleRad) do
    Dec(NSeg);

  if NSeg < 1 then
  begin
    ShowMessage('Arc sweep is too small to fit even one via segment. ' +
                'Try a smaller via diameter or larger arc.');
    Exit;
  end;

  // ------------------------------------------------------------------
  //  Inner row  —  NSeg + 1 markers per concentric arc
  //    Outer concentric arc : R + InnerOffMils
  //    Inner concentric arc : R - InnerOffMils  (= RInner)
  // ------------------------------------------------------------------
  for i := 0 to NSeg do
  begin
    AngleDeg := StartDeg + (i / NSeg) * TotalDeg;
    AngleRad := AngleDeg * Pi / 180.0;
    VX := Cos(AngleRad);
    VY := Sin(AngleRad);

    // Outer concentric arc (away from arc centre)
    CX := CXM + (R + InnerOffMils) * VX;
    CY := CYM + (R + InnerOffMils) * VY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);

    // Inner concentric arc (toward arc centre)
    CX := CXM + RInner * VX;
    CY := CYM + RInner * VY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);
  end;

  // ------------------------------------------------------------------
  //  Outer row  —  NSeg markers per concentric arc, staggered by θ/2
  //    Outer concentric arc : R + OuterOffMils
  //    Inner concentric arc : R - OuterOffMils  (placed only if > 0)
  // ------------------------------------------------------------------
  for i := 0 to NSeg - 1 do
  begin
    AngleDeg := StartDeg + ((i + 0.5) / NSeg) * TotalDeg;
    AngleRad := AngleDeg * Pi / 180.0;
    VX := Cos(AngleRad);
    VY := Sin(AngleRad);

    // Outer concentric arc
    CX := CXM + (R + OuterOffMils) * VX;
    CY := CYM + (R + OuterOffMils) * VY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);

    // Inner concentric arc — omit if the offset exceeds the arc radius.
    // (This is the corner case noted during design; a separate check will
    //  be added once the overall logic is validated.)
    ROuter := R - OuterOffMils;
    if ROuter > 0.0 then
    begin
      CX := CXM + ROuter * VX;
      CY := CYM + ROuter * VY;
      PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);
    end;
  end;
end;


// ============================================================================
//  MAIN ENTRY POINT
//  (Altium calls the procedure named "Run" when the script is executed.)
// ============================================================================

procedure Run;
Var
  Board        : IPCB_Board;
  Iterator     : IPCB_BoardIterator;
  Prim         : IPCB_Primitive;
  SelTrack     : IPCB_Track;
  SelArc       : IPCB_Arc;
  Layer        : TLayer;
  DiamMils     : Double;
  InnerOffMils : Double;
  OuterOffMils : Double;
  SelCount     : Integer;
begin
  // ------------------------------------------------------------------
  //  Obtain the current PCB document
  // ------------------------------------------------------------------
  Board := PCBServer.GetCurrentPCBBoard;
  if not Assigned(Board) then
  begin
    ShowMessage('No PCB document is currently active.');
    Exit;
  end;

  // ------------------------------------------------------------------
  //  Find the single selected track or arc
  // ------------------------------------------------------------------
  SelTrack := nil;
  SelArc   := nil;
  SelCount := 0;

  Iterator := Board.BoardIterator_Create;
  Iterator.SetState_FilterAll;
  Iterator.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject));

  Prim := Iterator.FirstPCBObject;
  while Assigned(Prim) do
  begin
    if Prim.Selected then
    begin
      Inc(SelCount);
      if Prim.ObjectId = eTrackObject then
        SelTrack := Prim
      else if Prim.ObjectId = eArcObject then
        SelArc := Prim;
    end;
    Prim := Iterator.NextPCBObject;
  end;
  Board.BoardIterator_Destroy(Iterator);

  if SelCount = 0 then
  begin
    ShowMessage('No track or arc segment is selected.' + #13#10 +
                'Please select exactly one segment and run again.');
    Exit;
  end;

  if SelCount > 1 then
  begin
    ShowMessage('More than one object is selected.' + #13#10 +
                'Please select exactly one track or arc segment and run again.');
    Exit;
  end;

  // ------------------------------------------------------------------
  //  Show parameter dialog
  // ------------------------------------------------------------------
  if not ShowParamDialog(DiamMils, InnerOffMils, OuterOffMils) then
    Exit;  // user cancelled

  // Basic validation
  if DiamMils <= 0.0 then
  begin ShowMessage('Via diameter must be greater than zero.'); Exit; end;

  if InnerOffMils <= 0.0 then
  begin ShowMessage('Inner row offset must be greater than zero.'); Exit; end;

  if OuterOffMils <= InnerOffMils then
  begin ShowMessage('Outer row offset must be greater than inner row offset.'); Exit; end;

  // ------------------------------------------------------------------
  //  Ensure M100 "Via Stitch Template" layer exists
  // ------------------------------------------------------------------
  PCBServer.PreProcess;

  Layer := EnsureViaStitchLayer(Board);

  // ------------------------------------------------------------------
  //  Dispatch to track or arc handler
  // ------------------------------------------------------------------
  if Assigned(SelTrack) then
    ProcessTrack(Board, SelTrack, Layer, DiamMils, InnerOffMils, OuterOffMils)
  else if Assigned(SelArc) then
    ProcessArc(Board, SelArc, Layer, DiamMils, InnerOffMils, OuterOffMils);

  PCBServer.PostProcess;

  // ------------------------------------------------------------------
  //  Refresh the view
  // ------------------------------------------------------------------
  Board.ViewManager_FullUpdate;
  Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);

  ShowMessage('Via stitch template markers placed successfully.');
end;
