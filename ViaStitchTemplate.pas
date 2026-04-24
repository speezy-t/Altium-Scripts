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
    Btn             := TButton.Create(Frm); Btn.Parent := Frm;
    Btn.Caption     := 'OK';
    Btn.Left        := 124; Btn.Top := 136; Btn.Width := 76;
    Btn.Default     := True;
    Btn.ModalResult := mrOK;

    Btn             := TButton.Create(Frm); Btn.Parent := Frm;
    Btn.Caption     := 'Cancel';
    Btn.Left        := 208; Btn.Top := 136; Btn.Width := 76;
    Btn.ModalResult := mrCancel;

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
Const
  kLayerName = 'Via Stitch Placement';
Var
  Target   : TLayer;
  LS       : IPCB_LayerStack;
  LO       : IPCB_LayerObject;
  Found    : Boolean;
begin
  Target := LayerUtils.MechanicalLayer(100);
  Found  := False;
  LS     := Board.LayerStack;

  // Iterate the live layer stack — works correctly in Altium 19+ / 26.x
  LO := LS.FirstLayer;
  while Assigned(LO) do
  begin
    if LO.LayerID = Target then
    begin
      Found := True;
      // Silently correct the name if it differs
      if LO.Name <> kLayerName then
        LO.Name := kLayerName;
      Break;
    end;
    LO := LS.NextLayer(LO);
  end;

  if not Found then
  begin
    // Layer does not exist — add it
    LO := LS.AddNewMechanicalLayer;
    if Assigned(LO) then
    begin
      LO.Name := kLayerName;
      Target  := LO.LayerID;   // use the ID assigned by Altium
    end
    else
      ShowMessage('Could not create "' + kLayerName + '" automatically. ' +
                  'Please add it manually in the Layer Stack Manager, then re-run.');
  end;

  Result := Target;
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

// Returns the largest NSeg such that the chord at the given radius with angular
// step (TotalRad / NSeg) is strictly greater than DiamMils.
// Returns 0 if the constraint cannot be satisfied (radius too small).
function CalcArcNSeg(TotalRad, RadiusMils, DiamMils : Double) : Integer;
Var
  MinAngleRad : Double;
  N           : Integer;
begin
  if (RadiusMils <= 0.0) or (DiamMils >= 2.0 * RadiusMils) then
  begin
    Result := 0;
    Exit;
  end;
  // Minimum angular step so that chord = 2·r·sin(θ/2) > DiamMils
  MinAngleRad := 2.0 * SafeArcSin(DiamMils / (2.0 * RadiusMils));
  N := Trunc(TotalRad / MinAngleRad);
  while (N > 0) and (TotalRad / N <= MinAngleRad) do
    Dec(N);
  Result := N;
end;

// Places one concentric arc of via markers.
//   CXM, CYM   : arc centre in mils
//   RadiusMils : radius of this concentric arc in mils
//   StartDeg   : start angle in degrees (Altium CCW convention)
//   TotalDeg   : total CCW sweep in degrees
//   NSeg       : number of equal angular segments  (NSeg+1 markers, endpoints included)
//   Stagger    : if True, positions are offset by half-pitch (NSeg markers, no endpoints)
procedure PlaceConcentricRow(Board      : IPCB_Board;
                             Layer      : TLayer;
                             CXM, CYM  : Double;
                             RadiusMils : Double;
                             StartDeg   : Double;
                             TotalDeg   : Double;
                             NSeg       : Integer;
                             DiamMils   : Double;
                             Stagger    : Boolean);
Var
  i        : Integer;
  Count    : Integer;
  AngleDeg : Double;
  AngleRad : Double;
  VX, VY   : Double;
  CX, CY   : Double;
begin
  if Stagger then Count := NSeg       // outer row: NSeg markers between endpoints
  else            Count := NSeg + 1;  // inner row: NSeg+1 markers including endpoints

  for i := 0 to Count - 1 do
  begin
    if Stagger then
      AngleDeg := StartDeg + ((i + 0.5) / NSeg) * TotalDeg
    else
      AngleDeg := StartDeg + (i        / NSeg) * TotalDeg;

    AngleRad := AngleDeg * Pi / 180.0;
    VX := Cos(AngleRad);
    VY := Sin(AngleRad);

    CX := CXM + RadiusMils * VX;
    CY := CYM + RadiusMils * VY;
    PlaceCircle(Board, Layer, MilsToCoord(CX), MilsToCoord(CY), DiamMils / 2.0);
  end;
end;

procedure ProcessArc(Board        : IPCB_Board;
                     ArcSeg       : IPCB_Arc;
                     Layer        : TLayer;
                     DiamMils     : Double;
                     InnerOffMils : Double;
                     OuterOffMils : Double);
Var
  CXM, CYM   : Double;   // arc centre in mils
  R          : Double;   // arc radius in mils
  StartDeg   : Double;   // start angle in degrees (Altium CCW convention)
  TotalDeg   : Double;   // total CCW sweep in degrees
  TotalRad   : Double;   // total CCW sweep in radians

  // The four concentric arc radii
  RIS : Double;   // inner row, small side  (R - InnerOffMils)
  RIB : Double;   // inner row, big side    (R + InnerOffMils)
  ROS : Double;   // outer row, small side  (R - OuterOffMils)
  ROB : Double;   // outer row, big side    (R + OuterOffMils)

  // Segment counts driven by the inner arcs on each side.
  // Outer arcs inherit their count from the inner arc on the same side so
  // that outer markers fall angularly between the inner markers (true stagger).
  NSegIS : Integer;   // inner small — also governs outer small
  NSegIB : Integer;   // inner big   — also governs outer big
begin
  CXM      := CoordToMils(ArcSeg.XCenter);
  CYM      := CoordToMils(ArcSeg.YCenter);
  R        := CoordToMils(ArcSeg.Radius);
  StartDeg := ArcSeg.StartAngle;

  // Total CCW sweep; add 360 if EndAngle <= StartAngle
  TotalDeg := ArcSeg.EndAngle - StartDeg;
  if TotalDeg <= 0.0 then TotalDeg := TotalDeg + 360.0;
  TotalRad := TotalDeg * Pi / 180.0;

  // Compute the four radii
  RIS := R - InnerOffMils;
  RIB := R + InnerOffMils;
  ROS := R - OuterOffMils;
  ROB := R + OuterOffMils;

  // Compute segment counts from inner arcs only
  NSegIS := CalcArcNSeg(TotalRad, RIS, DiamMils);
  NSegIB := CalcArcNSeg(TotalRad, RIB, DiamMils);

  // Validate — abort if the inner small arc (most constrained) is unworkable
  if RIS <= 0.0 then
  begin
    ShowMessage(Format('Inner row offset (%.2f mils) equals or exceeds the arc ' +
                       'radius (%.2f mils). Cannot place inner-side markers.',
                       [InnerOffMils, R]));
    Exit;
  end;
  if NSegIS < 1 then
  begin
    ShowMessage(Format('Arc sweep is too small for the inner small arc (r=%.2f mils). ' +
                       'Try a smaller via diameter or larger arc.', [RIS]));
    Exit;
  end;
  if NSegIB < 1 then
  begin
    ShowMessage(Format('Arc sweep is too small for the inner big arc (r=%.2f mils). ' +
                       'Try a smaller via diameter or larger arc.', [RIB]));
    Exit;
  end;

  // ------------------------------------------------------------------
  //  Inner row — endpoints included (Stagger = False)
  // ------------------------------------------------------------------
  PlaceConcentricRow(Board, Layer, CXM, CYM, RIS,
                     StartDeg, TotalDeg, NSegIS, DiamMils, False);
  PlaceConcentricRow(Board, Layer, CXM, CYM, RIB,
                     StartDeg, TotalDeg, NSegIB, DiamMils, False);

  // ------------------------------------------------------------------
  //  Outer row — staggered by half of the inner pitch for the same side
  //  (Stagger = True). Outer arcs inherit NSegIS / NSegIB so markers
  //  land exactly between the corresponding inner markers radially.
  //  The small-side outer arc is skipped silently if its radius <= 0.
  // ------------------------------------------------------------------
  PlaceConcentricRow(Board, Layer, CXM, CYM, ROB,
                     StartDeg, TotalDeg, NSegIB, DiamMils, True);

  if ROS > 0.0 then
    PlaceConcentricRow(Board, Layer, CXM, CYM, ROS,
                       StartDeg, TotalDeg, NSegIS, DiamMils, True);
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
