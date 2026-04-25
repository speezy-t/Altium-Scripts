{ ===========================================================================
  DrawSolderMaskRegion.pas
  Altium Designer 26.x  –  DelphiScript

  PURPOSE
  -------
  Places a rectangular solder-mask opening region that is geometrically
  aligned to a selected copper track on the Top or Bottom signal layer.

  Because Altium renders track/arc solder-mask expansions with rounded
  end-caps, this script instead draws an explicit rectangular region on
  the corresponding solder-mask layer (eTopSolder / eBottomSolder) so
  that the opening meets pad edges cleanly without overlapping them.

  PRE-CONDITIONS
  --------------
  * Exactly one track must be selected before running the script.
  * The track must reside on the Top or Bottom copper layer.
    Any other selection (arc, via, no object, wrong layer …) is rejected
    with a descriptive error message.

  DIALOG PARAMETERS  (all values entered in mils)
  -------------------------------------------------
  Expansion   – how far beyond the physical edge of the trace (i.e. beyond
                Width/2) the two long edges of the rectangle extend.
                Example: trace width 10 mil, expansion 25 mil  →  the
                rectangle spans ±30 mil from the trace centre-line.

  Left Offset – how far the LEFT short edge of the rectangle is set inward
                (towards the right endpoint) measured along the trace axis.
                "Left" always refers to the endpoint with the more-negative
                X coordinate (Y tiebreaker for vertical traces).
                Positive value = rectangle does not reach the left endpoint.
                Default: 0 (rectangle flush with the left endpoint).

  Right Offset– same as Left Offset, but for the RIGHT short edge.
                Default: 0.

  GEOMETRY
  --------
  Let P_L = "left" endpoint, P_R = "right" endpoint.
  u  = unit vector along the trace (P_L → P_R)
  v  = unit vector 90° CCW from u (perpendicular, "upward" relative to trace)
  half = Width/2 + Expansion

  The four rectangle corners in order:
    A  =  P_L + LeftOffset·u  +  half·v        (top-left)
    B  =  P_R − RightOffset·u +  half·v        (top-right)
    C  =  P_R − RightOffset·u −  half·v        (bottom-right)
    D  =  P_L + LeftOffset·u  −  half·v        (bottom-left)

  REGION CREATION STRATEGY
  ------------------------
  The IPCB_Region Outline API is not reliably accessible from DelphiScript
  in Altium 26.  Instead this script replicates the manual workflow:
    1. Place four track segments on the solder mask layer that connect the
       four rectangle corners (A→B, B→C, C→D, D→A).
    2. Deselect all objects, then select only those four segments.
    3. Run PCB:CreateRegionFromSelectedPrimitives — the same command that
       Tools → Convert → Create Regions from Selected Primitives invokes.
    4. Remove the four helper track segments, leaving only the region.

  UNDO
  ----
  The placement is wrapped in PCBServer.PreProcess / PostProcess so the
  user can undo it with a single Ctrl+Z.

  =========================================================================== }


{ ---------------------------------------------------------------------------
  GetSelectedTrack
  Searches the board for selected tracks on the Top or Bottom copper layer.
  Returns TRUE and sets Track if exactly one qualifying track is found.
  Displays an appropriate error dialog and returns FALSE otherwise.
  --------------------------------------------------------------------------- }
function GetSelectedTrack(Board     : IPCB_Board;
                          var Track : IPCB_Track) : Boolean;
var
  Iter     : IPCB_BoardIterator;
  Obj      : IPCB_Primitive;
  SelCount : Integer;
begin
  Result   := False;
  Track    := Nil;
  SelCount := 0;

  Iter := Board.BoardIterator_Create;
  Iter.AddFilter_ObjectSet(MkSet(eTrackObject));
  Iter.AddFilter_LayerSet(AllLayers);

  Obj := Iter.FirstPCBObject;
  while Obj <> Nil do
  begin
    if Obj.Selected then
    begin
      if (Obj.Layer = eTopLayer) or (Obj.Layer = eBottomLayer) then
      begin
        Inc(SelCount);
        Track := Obj;
      end;
    end;
    Obj := Iter.NextPCBObject;
  end;
  Board.BoardIterator_Destroy(Iter);

  if SelCount = 0 then
  begin
    ShowMessage(
      'Error: No qualifying object selected.' + #13#10 + #13#10 +
      'Please select exactly one track on the Top or Bottom' + #13#10 +
      'copper layer, then re-run the script.' + #13#10 + #13#10 +
      'Note: arcs are not yet supported by this script.'
    );
    Exit;
  end;

  if SelCount > 1 then
  begin
    ShowMessage(
      'Error: Multiple tracks are selected (' + IntToStr(SelCount) + ').' + #13#10 + #13#10 +
      'Please select exactly one track and re-run the script.'
    );
    Exit;
  end;

  Result := True;
end;


{ ---------------------------------------------------------------------------
  ShowParamDialog
  Builds and displays a modal dialog that collects the three user parameters.
  Sets Cancelled := True if the user closes/cancels without clicking OK.
  All returned values are in mils (floating-point).

  NOTE on parsing: Altium's DelphiScript does not expose the standard Pascal
  Val() procedure. StrToFloatDef(str, fallback) is used instead — it returns
  the fallback (-1) when the string cannot be parsed, which then fails the
  >= 0 validation check and re-prompts the user.

  NOTE on Font.Style: DelphiScript does not support bare empty-set literals
  ([]) as an r-value assignment, so that property is left at its default.
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
    Dlg.Width       := 340;
    Dlg.Height      := 250;
    Dlg.Position    := poScreenCenter;
    Dlg.BorderStyle := bsDialog;

    { Expansion }
    LblExp         := TLabel.Create(Dlg);
    LblExp.Parent  := Dlg;
    LblExp.Caption := 'Expansion (mils):';
    LblExp.Left    := 16;
    LblExp.Top     := 22;
    LblExp.Width   := 150;

    EdtExp        := TEdit.Create(Dlg);
    EdtExp.Parent := Dlg;
    EdtExp.Left   := 196;
    EdtExp.Top    := 18;
    EdtExp.Width  := 110;
    EdtExp.Text   := '0';

    { Left Offset }
    LblLeft         := TLabel.Create(Dlg);
    LblLeft.Parent  := Dlg;
    LblLeft.Caption := 'Left offset (mils):';
    LblLeft.Left    := 16;
    LblLeft.Top     := 62;
    LblLeft.Width   := 150;

    EdtLeft        := TEdit.Create(Dlg);
    EdtLeft.Parent := Dlg;
    EdtLeft.Left   := 196;
    EdtLeft.Top    := 58;
    EdtLeft.Width  := 110;
    EdtLeft.Text   := '0';

    { Right Offset }
    LblRight         := TLabel.Create(Dlg);
    LblRight.Parent  := Dlg;
    LblRight.Caption := 'Right offset (mils):';
    LblRight.Left    := 16;
    LblRight.Top     := 102;
    LblRight.Width   := 150;

    EdtRight        := TEdit.Create(Dlg);
    EdtRight.Parent := Dlg;
    EdtRight.Left   := 196;
    EdtRight.Top    := 98;
    EdtRight.Width  := 110;
    EdtRight.Text   := '0';

    { Helper note }
    LblNote         := TLabel.Create(Dlg);
    LblNote.Parent  := Dlg;
    LblNote.Caption := '"Left" = endpoint with more-negative X coordinate.';
    LblNote.Left    := 16;
    LblNote.Top     := 140;
    LblNote.Width   := 300;

    { OK button }
    BtnOK             := TButton.Create(Dlg);
    BtnOK.Parent      := Dlg;
    BtnOK.Caption     := 'OK';
    BtnOK.Left        := 140;
    BtnOK.Top         := 172;
    BtnOK.Width       := 80;
    BtnOK.ModalResult := mrOK;
    BtnOK.Default     := True;

    { Cancel button }
    BtnCancel             := TButton.Create(Dlg);
    BtnCancel.Parent      := Dlg;
    BtnCancel.Caption     := 'Cancel';
    BtnCancel.Left        := 232;
    BtnCancel.Top         := 172;
    BtnCancel.Width       := 80;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Cancel      := True;

    { Run dialog in a validation loop }
    ValidationOK := False;
    while not ValidationOK do
    begin
      if Dlg.ShowModal <> mrOK then
        Exit;   { user cancelled – Cancelled stays True }

      ValidationOK := True;

      { StrToFloatDef returns -1 on a parse failure, which then fails the
        >= 0 check below and re-prompts the user with a clear message. }

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
  ComputeRegionVertices
  Calculates the four corner coordinates (in Altium internal units) of the
  rotated rectangle.

  All *Coord parameters must already be in Altium internal units
  (use MilsToCoord before calling this procedure).

  Corner labelling (viewed from above, trace running left → right):
    A ------- B
    |         |
    D ------- C
  --------------------------------------------------------------------------- }
procedure ComputeRegionVertices(Track            : IPCB_Track;
                                ExpansionCoord   : TCoord;
                                LeftOffsetCoord  : TCoord;
                                RightOffsetCoord : TCoord;
                                var Ax, Ay       : TCoord;
                                var Bx, By       : TCoord;
                                var Cx, Cy       : TCoord;
                                var Dx, Dy       : TCoord);
var
  Lx, Ly       : Double;
  Rx, Ry       : Double;
  dRawX, dRawY : Double;
  TraceLen     : Double;
  ux, uy       : Double;
  vx, vy       : Double;
  Half         : Double;
  Lo, Ro       : Double;
begin
  { Assign "left" and "right" endpoints.
    Left = more-negative X; Y is the tiebreaker for vertical tracks. }
  if (Track.X1 < Track.X2) or
     ((Track.X1 = Track.X2) and (Track.Y1 < Track.Y2)) then
  begin
    Lx := Track.X1;   Ly := Track.Y1;
    Rx := Track.X2;   Ry := Track.Y2;
  end
  else
  begin
    Lx := Track.X2;   Ly := Track.Y2;
    Rx := Track.X1;   Ry := Track.Y1;
  end;

  dRawX    := Rx - Lx;
  dRawY    := Ry - Ly;
  TraceLen := Sqrt(dRawX * dRawX + dRawY * dRawY);

  if TraceLen < 1 then
  begin
    Ax := Round(Lx); Ay := Round(Ly);
    Bx := Ax;        By := Ay;
    Cx := Ax;        Cy := Ay;
    Dx := Ax;        Dy := Ay;
    ShowMessage('Warning: The selected track has zero (or near-zero) length. ' +
                'Region placement skipped.');
    Exit;
  end;

  ux := dRawX / TraceLen;
  uy := dRawY / TraceLen;

  { Perpendicular unit vector (90° CCW) }
  vx := -uy;
  vy :=  ux;

  Half := (Track.Width / 2) + ExpansionCoord;
  Lo   := LeftOffsetCoord;
  Ro   := RightOffsetCoord;

  { A: top-left }
  Ax := Round(Lx + Lo * ux + Half * vx);
  Ay := Round(Ly + Lo * uy + Half * vy);

  { B: top-right }
  Bx := Round(Rx - Ro * ux + Half * vx);
  By := Round(Ry - Ro * uy + Half * vy);

  { C: bottom-right }
  Cx := Round(Rx - Ro * ux - Half * vx);
  Cy := Round(Ry - Ro * uy - Half * vy);

  { D: bottom-left }
  Dx := Round(Lx + Lo * ux - Half * vx);
  Dy := Round(Ly + Lo * uy - Half * vy);
end;


{ ---------------------------------------------------------------------------
  MakeHelperTrack
  Creates a single track segment on TargetLayer between (X1,Y1) and (X2,Y2),
  registers it with the board, and returns the object reference so the caller
  can select and later remove it.
  Must be called inside a PreProcess / PostProcess block.
  --------------------------------------------------------------------------- }
function MakeHelperTrack(Board       : IPCB_Board;
                         TargetLayer : TLayer;
                         X1, Y1      : TCoord;
                         X2, Y2      : TCoord) : IPCB_Track;
var
  T : IPCB_Track;
begin
  T := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
  T.X1    := X1;
  T.Y1    := Y1;
  T.X2    := X2;
  T.Y2    := Y2;
  T.Layer := TargetLayer;
  T.Width := MilsToCoord(1);   { minimal width – these are construction lines }

  Board.AddPCBObject(T);
  PCBServer.SendMessageToRobots(
    Board.I_ObjectAddress,
    c_Broadcast,
    PCBM_BoardRegisteration,
    T.I_ObjectAddress
  );

  Result := T;
end;


{ ---------------------------------------------------------------------------
  PlaceRegion
  Implements the lines-then-convert strategy:

    1. Place four track segments on the solder mask layer that trace the
       four edges of the rectangle (A→B, B→C, C→D, D→A).
    2. Deselect all board objects, then select only those four segments.
    3. Invoke PCB:CreateRegionFromSelectedPrimitives — the same underlying
       command as Tools → Convert → Create Regions from Selected Primitives.
    4. Remove the four helper segments.

  Must be called inside a PCBServer.PreProcess / PostProcess block.
  --------------------------------------------------------------------------- }
procedure PlaceRegion(Board       : IPCB_Board;
                      TargetLayer : TLayer;
                      Ax, Ay      : TCoord;
                      Bx, By      : TCoord;
                      Cx, Cy      : TCoord;
                      Dx, Dy      : TCoord);
var
  T1, T2, T3, T4 : IPCB_Track;
begin
  { --- Step 1: place the four boundary segments --- }
  T1 := MakeHelperTrack(Board, TargetLayer, Ax, Ay, Bx, By);  { top edge    }
  T2 := MakeHelperTrack(Board, TargetLayer, Bx, By, Cx, Cy);  { right edge  }
  T3 := MakeHelperTrack(Board, TargetLayer, Cx, Cy, Dx, Dy);  { bottom edge }
  T4 := MakeHelperTrack(Board, TargetLayer, Dx, Dy, Ax, Ay);  { left edge   }

  { --- Step 2: deselect everything, then select only our four segments ---
    RunProcess('PCB:DeselAll') clears the board selection without needing
    to iterate every object manually. }
  ResetParameters;
  RunProcess('PCB:DeselAll');

  T1.Selected := True;
  T2.Selected := True;
  T3.Selected := True;
  T4.Selected := True;

  { --- Step 3: convert selected primitives to a region ---
    This is the programmatic equivalent of:
    Tools → Convert → Create Regions from Selected Primitives }
  ResetParameters;
  RunProcess('PCB:CreateRegionFromSelectedPrimitives');

  { --- Step 4: remove the helper track segments --- }
  Board.RemovePCBObject(T1);
  Board.RemovePCBObject(T2);
  Board.RemovePCBObject(T3);
  Board.RemovePCBObject(T4);
end;


{ ===========================================================================
  DrawSolderMaskRegion  –  SCRIPT ENTRY POINT
  =========================================================================== }
procedure DrawSolderMaskRegion;
var
  Board       : IPCB_Board;
  Track       : IPCB_Track;
  TargetLayer : TLayer;

  Expansion   : Double;
  LeftOffset  : Double;
  RightOffset : Double;
  Cancelled   : Boolean;

  Ax, Ay : TCoord;
  Bx, By : TCoord;
  Cx, Cy : TCoord;
  Dx, Dy : TCoord;
begin
  { 1. Obtain active PCB document }
  Board := PCBServer.GetCurrentPCBBoard;
  if Board = Nil then
  begin
    ShowMessage('Error: No PCB document is currently active.' + #13#10 +
                'Please open a PCB file before running this script.');
    Exit;
  end;

  { 2. Locate and validate the selected track }
  Track := Nil;
  if not GetSelectedTrack(Board, Track) then
    Exit;

  { 3. Resolve the target solder-mask layer }
  if Track.Layer = eTopLayer then
    TargetLayer := eTopSolder
  else
    TargetLayer := eBottomSolder;

  { 4. Collect parameters from the user }
  ShowParamDialog(Expansion, LeftOffset, RightOffset, Cancelled);
  if Cancelled then Exit;

  { 5. Compute the four rectangle corners }
  ComputeRegionVertices(
    Track,
    MilsToCoord(Expansion),
    MilsToCoord(LeftOffset),
    MilsToCoord(RightOffset),
    Ax, Ay,
    Bx, By,
    Cx, Cy,
    Dx, Dy
  );

  { 6. Place the region (undo-safe transaction) }
  PCBServer.PreProcess;
  try
    PlaceRegion(Board, TargetLayer, Ax, Ay, Bx, By, Cx, Cy, Dx, Dy);
  finally
    PCBServer.PostProcess;
  end;

  { 7. Refresh the board view }
  Board.ViewManager_FullUpdate;

  ShowMessage(
    'Solder mask region placed successfully.' + #13#10 +
    'Layer: ' + Board.LayerName(TargetLayer)
  );
end;
