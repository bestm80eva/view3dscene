{
  Copyright 2006-2017 Michalis Kamburelis.

  This file is part of "view3dscene".

  "view3dscene" is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  "view3dscene" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with "view3dscene"; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA

  ----------------------------------------------------------------------------
}

{ Lights editor in view3dscene. }
unit V3DSceneLightsEditor;

{$I v3dsceneconf.inc}

interface

uses Classes, CastleWindow, CastleSceneManager, CastleScene;

type
  TInternalScene = class(TCastleScene)
    constructor Create(AOwner: TComponent); override;
  end;

var
  MenuLightsEditor: TMenuItemChecked;

function LightsEditorIsOpen: boolean;

procedure LightsEditorOpen(const ASceneManager: TCastleSceneManager;
  const AWindow: TCastleWindowCustom; const AWindowMarginTop: Integer);
procedure LightsEditorClose;

implementation

uses SysUtils, CastleColors,
  CastleVectors, X3DNodes, CastleOnScreenMenu, CastleBoxes, Castle3D,
  CastleMessages, CastleUtils, CastleGLUtils, CastleUIControls,
  CastleRectangles, CastleControls,
  V3DSceneImages;

constructor TInternalScene.Create(AOwner: TComponent);
begin
  inherited;
  Collides := false;
  Pickable := false;
  CastShadowVolumes := false;
  ExcludeFromStatistics := true;
end;

{ TCastleOnScreenMenu descendants -------------------------------------------- }

type
  TV3DOnScreenMenu = class(TCastleOnScreenMenu)
  public
    constructor Create(AOwner: TComponent); override;
    procedure AddTitle(const S: string);
  end;

  TLightMenu = class;
  THeadLightMenu = class;

  TString3 = array [0..2] of string;

  { Three float sliders to control TVector3Single value. }
  TMenuVector3Sliders = class(TComponent)
  strict private
    Floats: array [0..2] of TCastleFloatSlider;
    FOnChange: TNotifyEvent;
    procedure ChildSliderChanged(Sender: TObject);
    function GetValue: TVector3Single;
    procedure SetValue(const AValue: TVector3Single);
  public
    constructor Create(const AOwner: TComponent;
      const Range: TBox3D; const AValue: TVector3Single); reintroduce; overload;
    constructor Create(const AOwner: TComponent;
      const Min, Max: Single; const AValue: TVector3Single); reintroduce; overload;
    procedure AddToMenu(const Menu: TCastleOnScreenMenu;
      const TitleBase, Title0, Title1, Title2: string);
    property Value: TVector3Single read GetValue write SetValue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TLightsMenu = class(TV3DOnScreenMenu)
  strict private
    AmbientColorSlider: TMenuVector3Sliders;
    { collected lights of the scene }
    Lights: TX3DNodeList;
    { seen headlight, if any }
    Headlight: TAbstractLightNode;
    LightMenu: TLightMenu;
    HeadLightMenu: THeadLightMenu;
    procedure AddLight(Node: TX3DNode);
    procedure DestructionNotification(Node: TX3DNode);
    procedure ClickEditLight(Sender: TObject);
    procedure ClickEditHeadlight(Sender: TObject);
    procedure ClickClose(Sender: TObject);
    procedure AmbientColorChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Do a partial destruction: remove everything that can have connections
      to existing scene. }
    procedure ClearLights;
  end;

  TLightMenu = class(TV3DOnScreenMenu)
  strict private
    Light: TAbstractLightNode;
    ColorSlider: TMenuVector3Sliders;
    IntensitySlider: TCastleFloatSlider;
    AmbientIntensitySlider: TCastleFloatSlider;
    OnToggle: TCastleMenuToggle;
    LocationSlider: TMenuVector3Sliders;
    procedure LocationChanged(Sender: TObject);
    procedure ColorChanged(Sender: TObject);
    procedure IntensityChanged(Sender: TObject);
    procedure AmbientIntensityChanged(Sender: TObject);
    procedure ClickOn(Sender: TObject);
    procedure ClickShadowsMenu(Sender: TObject);
  strict protected
    procedure ClickBack(Sender: TObject); virtual;
  public
    constructor Create(AOwner: TComponent; ALight: TAbstractLightNode); reintroduce;
    procedure AfterCreate;
    procedure Update(const SecondsPassed: Single;
      var HandleInput: boolean); override;
    procedure UpdateLightLocation;
  end;

  TPositionalLightMenu = class(TLightMenu)
  strict private
    Light: TAbstractPositionalLightNode;
    AttenuationSlider: TMenuVector3Sliders;
    procedure AttenuationChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; ALight: TAbstractPositionalLightNode); reintroduce;
  end;

  TSpot1LightMenu = class(TPositionalLightMenu)
  strict private
    Light: TSpotLightNode_1;
    CutOffAngleSlider: TCastleFloatSlider;
    DropOffRateSlider: TCastleFloatSlider;
    procedure CutOffAngleChanged(Sender: TObject);
    procedure DropOffRateChanged(Sender: TObject);
    procedure ClickDirection(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; ALight: TSpotLightNode_1); reintroduce;
  end;

  TSpotLightMenu = class(TPositionalLightMenu)
  strict private
    Light: TSpotLightNode;
    CutOffAngleSlider: TCastleFloatSlider;
    BeamWidthSlider: TCastleFloatSlider;
    procedure CutOffAngleChanged(Sender: TObject);
    procedure BeamWidthChanged(Sender: TObject);
    procedure ClickDirection(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; ALight: TSpotLightNode); reintroduce;
  end;

  TDirectionalLightMenu = class(TLightMenu)
  strict private
    Light: TAbstractDirectionalLightNode;
    procedure ClickDirection(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; ALight: TAbstractDirectionalLightNode); reintroduce;
  end;

  THeadLightMenu = class(TV3DOnScreenMenu)
  strict private
    Headlight: TAbstractLightNode;
    AmbientIntensitySlider: TCastleFloatSlider;
    ColorSlider: TMenuVector3Sliders;
    IntensitySlider: TCastleFloatSlider;
    AttenuationSlider: TMenuVector3Sliders;
    procedure ColorChanged(Sender: TObject);
    procedure AttenuationChanged(Sender: TObject);
    procedure AmbientIntensityChanged(Sender: TObject);
    procedure IntensityChanged(Sender: TObject);
    procedure ClickBack(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; AHeadlight: TAbstractLightNode); reintroduce;
  end;

  TCastle2ExponentSlider = class(TCastleIntegerSlider)
    function ValueToStr(const AValue: Integer): string; override;
  end;

  TShadowsMenu = class(TV3DOnScreenMenu)
  strict private
    Light: TAbstractLightNode;
    ShadowsToggle: TCastleMenuToggle;
    ShadowVolumesToggle: TCastleMenuToggle;
    ShadowVolumesMainToggle: TCastleMenuToggle;
    SliderMapSizeExponent: TCastle2ExponentSlider;
    SliderMapBias: TCastleFloatSlider;
    SliderMapScale: TCastleFloatSlider;
    CurrentProjectionLabel: TCastleLabel;
    procedure ClickShadows(Sender: TObject);
    procedure ClickShadowVolumes(Sender: TObject);
    procedure ClickShadowVolumesMain(Sender: TObject);
    procedure ClickRecalculateProjection(Sender: TObject);
    function RequiredDefaultShadowMap: TGeneratedShadowMapNode;
    procedure MapSizeExponentChanged(Sender: TObject);
    procedure MapBiasChanged(Sender: TObject);
    procedure MapScaleChanged(Sender: TObject);
    function GetMapSizeExponent: Integer;
    procedure SetMapSizeExponent(const Value: Integer);
    function GetMapBias: Single;
    procedure SetMapBias(const Value: Single);
    function GetMapScale: Single;
    procedure SetMapScale(const Value: Single);
    property MapSizeExponent: Integer read GetMapSizeExponent write SetMapSizeExponent;
    property MapBias: Single read GetMapBias write SetMapBias;
    property MapScale: Single read GetMapScale write SetMapScale;
  strict protected
    procedure ClickBack(Sender: TObject); virtual;
    procedure UpdateCurrentProjectionLabel(const ALabel: TCastleLabel); virtual;
  public
    ParentLightMenu: TLightMenu;
    constructor Create(AOwner: TComponent; ALight: TAbstractLightNode); reintroduce;
    procedure AfterCreate;
    procedure Update(const SecondsPassed: Single;
      var HandleInput: boolean); override;
  end;

  TSpotLightShadowsMenu = class(TShadowsMenu)
  strict private
    Light: TSpotLightNode;
  strict protected
    procedure UpdateCurrentProjectionLabel(const ALabel: TCastleLabel); override;
  public
    constructor Create(AOwner: TComponent; ALight: TSpotLightNode); reintroduce;
  end;

  TDirectionalLightShadowsMenu = class(TShadowsMenu)
  strict private
    Light: TAbstractDirectionalLightNode;
  strict protected
    procedure UpdateCurrentProjectionLabel(const ALabel: TCastleLabel); override;
  public
    constructor Create(AOwner: TComponent; ALight: TAbstractDirectionalLightNode); reintroduce;
  end;

{ global utils --------------------------------------------------------------- }

var
  { Local copy of scene manager and window for lights editor.
    Both @nil when we're closed, never @nil when we're open. }
  SceneManager: TCastleSceneManager;
  Window: TCastleWindowCustom;
  WindowMarginTop: Integer;

  LightsMenu: TLightsMenu;
  Gizmo: TInternalScene;
  GizmoTransform: T3DTransform;

procedure SetCurrentMenu(const NewValue: TCastleOnScreenMenu);
begin
  Window.Controls.MakeSingle(TCastleOnScreenMenu, NewValue, true);
end;

function LightsEditorIsOpen: boolean;
begin
  Result := SceneManager <> nil;
end;

{ Enlarged scene manager bounding box, never empty. }
function SceneManagerLargerBox(const SceneManager: TCastleSceneManager): TBox3D;
const
  DefaultSize = 10;
var
  BoxSizes: TVector3Single;
begin
  Result := SceneManager.Items.BoundingBox;
  if Result.IsEmpty then
    Result := Box3D(
      Vector3Single(-DefaultSize, -DefaultSize, -DefaultSize),
      Vector3Single( DefaultSize,  DefaultSize,  DefaultSize)) else
  begin
    BoxSizes := Result.Size;
    Result.Data[0] := Result.Data[0] - BoxSizes;
    Result.Data[1] := Result.Data[1] + BoxSizes;
  end;
end;

procedure IniitalizeGizmo;
const
  LightGizmoPivot: TVector2Single = (58.5, 146 - 58.5);
var
  RootNode: TX3DRootNode;
  Billboard: TBillboardNode;
  Shape: TShapeNode;
  Appearance: TAppearanceNode;
  Texture: TPixelTextureNode;
  Material: TMaterialNode;
  Quad: TQuadSetNode;
  QuadRect: TFloatRectangle;
  QuadCoords: TCoordinateNode;
  QuadTexCoords: TTextureCoordinateNode;
  Size: Single;
begin
  Size := SceneManagerLargerBox(SceneManager).AverageSize / 50;

  QuadRect.Left   := - LightGizmoPivot[0];
  QuadRect.Bottom := - LightGizmoPivot[1];
  QuadRect.Width  := Light_Gizmo.Width;
  QuadRect.Height := Light_Gizmo.Height;
  QuadRect := QuadRect.ScaleAround0(Size / Light_Gizmo.Width);

  QuadCoords := TCoordinateNode.Create;
  QuadCoords.FdPoint.Items.AssignArray([
    Vector3Single(QuadRect.Left , QuadRect.Bottom, 0),
    Vector3Single(QuadRect.Right, QuadRect.Bottom, 0),
    Vector3Single(QuadRect.Right, QuadRect.Top, 0),
    Vector3Single(QuadRect.Left , QuadRect.Top, 0)
  ]);

  QuadTexCoords := TTextureCoordinateNode.Create;
  QuadTexCoords.FdPoint.Items.AssignArray([
    Vector2Single(0, 0),
    Vector2Single(1, 0),
    Vector2Single(1, 1),
    Vector2Single(0, 1)
  ]);

  Quad := TQuadSetNode.Create;
  Quad.FdCoord.Value := QuadCoords;
  Quad.FdTexCoord.Value := QuadTexCoords;

  Material := TMaterialNode.Create;
  Material.ForcePureEmissive;
  Material.EmissiveColor := YellowRGB;

  Texture := TPixelTextureNode.Create;
  Texture.FdImage.Value := Light_Gizmo.MakeCopy;

  Appearance := TAppearanceNode.Create;
  Appearance.Material := Material;
  Appearance.Texture := Texture;
  Appearance.ShadowCaster := false;

  Shape := TShapeNode.Create;
  Shape.Geometry := Quad;
  Shape.Appearance := Appearance;

  Billboard := TBillboardNode.Create;
  Billboard.AxisOfRotation := ZeroVector3Single;
  Billboard.FdChildren.Add(Shape);

  RootNode := TX3DRootNode.Create;
  RootNode.FdChildren.Add(Billboard);

  Gizmo := TInternalScene.Create(Window);
  Gizmo.Load(RootNode, true);
  Gizmo.ProcessEvents := true; // for Billboard to work

  GizmoTransform := T3DTransform.Create(Window);
  GizmoTransform.Exists := false; // initially not existing
  GizmoTransform.Add(Gizmo);
end;

procedure LightsEditorOpen(const ASceneManager: TCastleSceneManager;
  const AWindow: TCastleWindowCustom; const AWindowMarginTop: Integer);
begin
  if SceneManager = ASceneManager then Exit;
  SceneManager := ASceneManager;
  Window := AWindow;
  WindowMarginTop := AWindowMarginTop;

  FreeAndNil(LightsMenu);
  LightsMenu := TLightsMenu.Create(nil);
  SetCurrentMenu(LightsMenu);
  MenuLightsEditor.Checked := true;

  { create GizmoTransform on demand }
  if GizmoTransform = nil then
    IniitalizeGizmo;
  SceneManager.Items.Add(GizmoTransform);
end;

procedure LightsEditorClose;
begin
  if SceneManager = nil then Exit;

  SetCurrentMenu(nil);

  { Just free Gizmo stuff, it will be recreated next time.
    This makes sure we update gizmo Size when loading different scenes. }
  // SceneManager.Items.Remove(GizmoTransform);
  FreeAndNil(GizmoTransform);
  FreeAndNil(Gizmo);

  { We don't immediately free here LightsMenu instance, because this is called
    also by TLightsMenu.ClickClose, and we should not free ourselves
    from our own method. So instead leave LightsMenu instance existing,
    but make sure (for speed) that it's not connected by DestructionNotifications
    to our scene. }
  if LightsMenu <> nil then
    LightsMenu.ClearLights;

  SceneManager := nil;
  Window := nil;
  MenuLightsEditor.Checked := false;
end;

function MessageInputQueryDirection(
  Window: TCastleWindowCustom; const Title: string;
  var Value: TVector3Single): boolean;
var
  Pos, Up: TVector3Single;
  s: string;
begin
  Result := false;
  s := Format('%g %g %g', [Value[0], Value[1], Value[2]]);
  if MessageInputQuery(Window, Title, s) then
  begin
    try
      if LowerCase(Trim(S)) = 'c' then
        SceneManager.Camera.GetView(Pos, Value, Up) else
        Value := Vector3SingleFromStr(s);
      Result := true;
    except
      on E: EConvertError do
        MessageOK(Window, 'Invalid vector 3 value : ' + E.Message);
    end;
  end;
end;

const
  { Although X3D allows attenuation[0] (constant) to be < 1, we don't allow it.
    That's because when rendering with fixed-function, it's not honored
    correctly: X3D spec says to do "1 / max(c1 + c2 * dL + c3 * dL^2, 1)"
    (makes sense: never make light brighter by attenuation),
    but fixed-function OpenGL doesn't do it (our shader rendering does it Ok). }
  AttenuationRange: TBox3D = (Data: ((1, 0, 0), (2, 2, 2)));

{ TMenuVector3Sliders -------------------------------------------------------- }

constructor TMenuVector3Sliders.Create(const AOwner: TComponent;
  const Range: TBox3D; const AValue: TVector3Single);
var
  I: Integer;
begin
  inherited Create(AOwner);
  for I := 0 to 2 do
  begin
    Floats[I] := TCastleFloatSlider.Create(Self);
    Floats[I].Min := Range.Data[0, I];
    Floats[I].Max := Range.Data[1, I];
    Floats[I].Value := AValue[I];
    Floats[I].OnChange := @ChildSliderChanged;
  end;
end;

constructor TMenuVector3Sliders.Create(const AOwner: TComponent;
  const Min, Max: Single; const AValue: TVector3Single);
begin
  Create(AOwner,
    Box3D(Vector3Single(Min, Min, Min), Vector3Single(Max, Max, Max)), AValue);
end;

procedure TMenuVector3Sliders.AddToMenu(const Menu: TCastleOnScreenMenu;
  const TitleBase, Title0, Title1, Title2: string);
var
  I: Integer;
  Title: TString3;
  TitleBaseSpace: string;
begin
  Title[0] := Title0;
  Title[1] := Title1;
  Title[2] := Title2;
  if TitleBase <> '' then
    TitleBaseSpace := TitleBase + ' ' else
    TitleBaseSpace := '';
  for I := 0 to 2 do
    Menu.Add(TitleBaseSpace + Title[I], Floats[I]);
end;

function TMenuVector3Sliders.GetValue: TVector3Single;
var
  I: Integer;
begin
  for I := 0 to 2 do
    Result[I] := Floats[I].Value;
end;

procedure TMenuVector3Sliders.SetValue(const AValue: TVector3Single);
var
  I: Integer;
begin
  for I := 0 to 2 do
    Floats[I].Value := AValue[I];
end;

procedure TMenuVector3Sliders.ChildSliderChanged(Sender: TObject);
begin
  if Assigned(OnChange) then
    OnChange(Self);
end;

{ TV3DOnScreenMenu ----------------------------------------------------------- }

constructor TV3DOnScreenMenu.Create(AOwner: TComponent);
begin
  inherited;
  BackgroundOpacityFocused := 0.3;
  BackgroundOpacityNotFocused := 0.2;

  Anchor(hpLeft, 20);
  Anchor(vpTop, -WindowMarginTop - 20);

  NonFocusableItemColor := Vector4Single(0.8, 0.8, 1, 1);
end;

procedure TV3DOnScreenMenu.AddTitle(const S: string);
begin
  Add(S);
end;

{ TLightsMenu ------------------------------------------------------- }

constructor TLightsMenu.Create(AOwner: TComponent);
var
  I: Integer;
  Light: TAbstractLightNode;
  LightEditButton: TCastleMenuButton;
begin
  inherited;

  Lights := TX3DNodeList.Create(false);

  AmbientColorSlider := TMenuVector3Sliders.Create(Self, 0, 1, RenderContext.GlobalAmbient);
  AmbientColorSlider.OnChange := @AmbientColorChanged;

  SceneManager.MainScene.RootNode.EnumerateNodes(TAbstractLightNode, @AddLight, false);

  AddTitle('Lights Editor:');
  for I := 0 to Lights.Count - 1 do
  begin
    Light := Lights[I] as TAbstractLightNode;
    LightEditButton := TCastleMenuButton.Create(Self);
    LightEditButton.Tag := I;
    LightEditButton.OnClick := @ClickEditLight;
    Add(Format('Edit %d: %s', [I, Light.NiceName]), LightEditButton);
  end;
  AmbientColorSlider.AddToMenu(Self, 'Global Ambient Light', 'Red', 'Green', 'Blue');
  Add('Edit Headlight', @ClickEditHeadlight);
  Add('Close Lights Editor', @ClickClose);
end;

destructor TLightsMenu.Destroy;
begin
  ClearLights;
  inherited;
end;

procedure TLightsMenu.ClearLights;
var
  I: Integer;
begin
  if Lights <> nil then
  begin
    for I := 0 to Lights.Count - 1 do
      Lights[I].RemoveDestructionNotification(@DestructionNotification);
  end;
  FreeAndNil(Lights);

  if Headlight <> nil then
  begin
    Headlight.RemoveDestructionNotification(@DestructionNotification);
    Headlight := nil;
  end;

  FreeAndNil(LightMenu);
  FreeAndNil(HeadLightMenu);
end;

procedure TLightsMenu.DestructionNotification(Node: TX3DNode);
var
  I: Integer;
begin
  { Disconnect our destruction notifications from all other lights.
    Do not disconnect from Node (that is now freed), since implementation
    of this node probably iterates now over it's DestructionNotifications list. }

  if Lights <> nil then
  begin
    for I := 0 to Lights.Count - 1 do
      if Node <> Lights[I] then
        Lights[I].RemoveDestructionNotification(@DestructionNotification);
    Lights.Clear;
  end;

  if (Headlight <> nil) and (Node <> Headlight) then
    Headlight.RemoveDestructionNotification(@DestructionNotification);
  Headlight := nil;

  { At one point I tried here to return to LightsMenu,
    and do InitializeLightsItems again.
    But this isn't such good idea, because when we release the scene
    to load a new one, we currently have empty SceneManager.MainScene
    or SceneManager.MainScene.RootNode, and we don't see any lights yet.
    So calling InitializeLightsItems again always fills the list with no lights...
    And we don't get any notifications when new scene is loaded (no such
    mechanism in engine now), so we don't show new lights.
    It's easier to just close lights editor (this also just destroys
    our instance), and force user to open it again if wanted. }

  LightsEditorClose;
end;

procedure TLightsMenu.AddLight(Node: TX3DNode);
begin
  if Lights.IndexOf(Node) = -1 then
  begin
    Lights.Add(Node);
    Node.AddDestructionNotification(@DestructionNotification);
  end;
end;

procedure TLightsMenu.ClickEditLight(Sender: TObject);
var
  LightIndex: Integer;
  Node: TAbstractLightNode;
begin
  FreeAndNil(LightMenu);
  LightIndex := (Sender as TCastleMenuButton).Tag;
  Node := Lights[LightIndex] as TAbstractLightNode;
  if Node is TSpotLightNode_1 then
    LightMenu := TSpot1LightMenu.Create(Self, TSpotLightNode_1(Node)) else
  if Node is TSpotLightNode then
    LightMenu := TSpotLightMenu.Create(Self, TSpotLightNode(Node)) else
  if Node is TAbstractDirectionalLightNode then
    LightMenu := TDirectionalLightMenu.Create(Self, TAbstractDirectionalLightNode(Node)) else
  if Node is TAbstractPositionalLightNode then
    LightMenu := TPositionalLightMenu.Create(Self, TAbstractPositionalLightNode(Node)) else
    { fallback on TLightMenu, although currently we just capture all
      possible descendants with specialized menu types above }
    LightMenu := TLightMenu.Create(Self, Node);
  LightMenu.AfterCreate;
  SetCurrentMenu(LightMenu);
end;

procedure TLightsMenu.ClickEditHeadlight(Sender: TObject);
var
  H: TLightInstance;
  NewHeadlight: TAbstractLightNode;
begin
  if SceneManager.HeadlightInstance(H) then
  begin
    FreeAndNil(HeadLightMenu);
    NewHeadlight := H.Node;
    HeadLightMenu := THeadLightMenu.Create(Self, NewHeadlight);
    SetCurrentMenu(HeadLightMenu);

    if Headlight <> NewHeadlight then
    begin
      if Headlight <> nil then
        Headlight.RemoveDestructionNotification(@DestructionNotification);
      Headlight := NewHeadlight;
      Headlight.AddDestructionNotification(@DestructionNotification);
    end;
  end else
    MessageOK(Window, 'No headlight in level.' +NL+ NL+
      'You have to turn on headlight first:' +NL+
      '- by menu item "View -> Headlight" (Ctrl+H),' +NL+
      '- or by editing the VRML/X3D model and setting NavigationInfo.headlight to TRUE.');
end;

procedure TLightsMenu.ClickClose(Sender: TObject);
begin
  LightsEditorClose;
end;

procedure TLightsMenu.AmbientColorChanged(Sender: TObject);
begin
  RenderContext.GlobalAmbient := AmbientColorSlider.Value;

  { TODO: We just directly set global paramater now.
    Default is equal to 0.2, 0.2, 0.2 default.
    This could be changed to control NavigationInfo.globalAmbient field
    (InstantReality extension that we plan to implement too,
    see http://doc.instantreality.org/documentation/nodetype/NavigationInfo/ ),
    and then we would keep GlobalAmbient at TCastleScene level. }
end;

{ TLightMenu ---------------------------------------------------------- }

constructor TLightMenu.Create(AOwner: TComponent; ALight: TAbstractLightNode);
var
  Box: TBox3D;
begin
  inherited Create(AOwner);

  Light := ALight;

  ColorSlider := TMenuVector3Sliders.Create(Self, 0, 1, Light.FdColor.Value);
  ColorSlider.OnChange := @ColorChanged;

  IntensitySlider := TCastleFloatSlider.Create(Self);
  IntensitySlider.Min := 0;
  IntensitySlider.Max := 1;
  IntensitySlider.Value := Light.FdIntensity.Value;
  IntensitySlider.OnChange := @IntensityChanged;

  AmbientIntensitySlider := TCastleFloatSlider.Create(Self);
  AmbientIntensitySlider.Min := 0;
  AmbientIntensitySlider.Max := 1;
  AmbientIntensitySlider.Value := Light.FdAmbientIntensity.Value;
  AmbientIntensitySlider.OnChange := @AmbientIntensityChanged;

  OnToggle := TCastleMenuToggle.Create(Self);
  OnToggle.Pressed := Light.FdOn.Value;
  OnToggle.OnClick := @ClickOn;

 { determine sensible lights positions.
    Box doesn't depend on Light.SceneLocation, to not change range each time
    --- but this causes troubles,
    as Light.SceneLocation may not fit within range,
    which is uncomfortable (works Ok, but not nice for user). }
  Box := SceneManagerLargerBox(SceneManager);
  LocationSlider := TMenuVector3Sliders.Create(Self, Box, Light.ProjectionSceneLocation);
  LocationSlider.OnChange := @LocationChanged;

  AddTitle('Edit ' + Light.NiceName + ':');
  ColorSlider.AddToMenu(Self, '', 'Red', 'Green', 'Blue');
  Add('Intensity', IntensitySlider);
  Add('Ambient Intensity', AmbientIntensitySlider);
  Add('On', OnToggle);
  LocationSlider.AddToMenu(Self, 'Location', 'X', 'Y', 'Z');
  Add('Shadows Settings...', @ClickShadowsMenu);

  GizmoTransform.Exists := true;
  { Make sure camera information is updated, to update billboard orientation.
    TODO: This should not be needed, should be handled on engine side to keep
    billboards updated. See TODO in CastleSceneCore unit. }
  GizmoTransform.CameraChanged(SceneManager.RequiredCamera);
  GizmoTransform.Translation := Light.ProjectionSceneLocation;
end;

procedure TLightMenu.AfterCreate;
begin
  Add('Back to Lights Menu', @ClickBack);
end;

procedure TLightMenu.ColorChanged(Sender: TObject);
begin
  Light.Color := ColorSlider.Value;
end;

procedure TLightMenu.IntensityChanged(Sender: TObject);
begin
  Light.Intensity := IntensitySlider.Value;
end;

procedure TLightMenu.AmbientIntensityChanged(Sender: TObject);
begin
  Light.AmbientIntensity := AmbientIntensitySlider.Value;
end;

procedure TLightMenu.ClickOn(Sender: TObject);
begin
  OnToggle.Pressed := not OnToggle.Pressed;
  Light.IsOn := OnToggle.Pressed;
end;

procedure TLightMenu.ClickShadowsMenu(Sender: TObject);
var
  ShadowsMenu: TShadowsMenu;
begin
  if Light is TSpotLightNode then
    ShadowsMenu := TSpotLightShadowsMenu.Create(Self, TSpotLightNode(Light))
  else
  if Light is TAbstractDirectionalLightNode then
    ShadowsMenu := TDirectionalLightShadowsMenu.Create(Self, TAbstractDirectionalLightNode(Light))
  else
    ShadowsMenu := TShadowsMenu.Create(Self, Light);
  ShadowsMenu.ParentLightMenu := Self;
  ShadowsMenu.AfterCreate;
  SetCurrentMenu(ShadowsMenu);
end;

procedure TLightMenu.LocationChanged(Sender: TObject);
begin
  Light.ProjectionSceneLocation := LocationSlider.Value;
  GizmoTransform.Translation := LocationSlider.Value;
end;

procedure TLightMenu.Update(const SecondsPassed: Single; var HandleInput: boolean);
begin
  inherited;
  UpdateLightLocation;
end;

procedure TLightMenu.UpdateLightLocation;
var
  V: TVector3Single;
begin
  { light location may change due to various things
    (it may be animated by X3D events, it may change when we turn on
    shadows:=TRUE for DirectionalLight...).
    So just update it continously. }
  V := Light.ProjectionSceneLocation;
  if not VectorsEqual(V, LocationSlider.Value) then
  begin
    LocationSlider.Value := V;
    GizmoTransform.Translation := V;
  end;
end;

procedure TLightMenu.ClickBack(Sender: TObject);
begin
  SetCurrentMenu(LightsMenu);
  GizmoTransform.Exists := false;
end;

{ TPositionalLightMenu ------------------------------------------------------- }

constructor TPositionalLightMenu.Create(AOwner: TComponent; ALight: TAbstractPositionalLightNode);
begin
  inherited Create(AOwner, ALight);
  Light := ALight;

  AttenuationSlider := TMenuVector3Sliders.Create(Self,
    AttenuationRange, Light.FdAttenuation.Value);
  AttenuationSlider.OnChange := @AttenuationChanged;

  AttenuationSlider.AddToMenu(Self, 'Attenuation', 'Constant' , 'Linear', 'Quadratic');
end;

procedure TPositionalLightMenu.AttenuationChanged(Sender: TObject);
begin
  Light.Attenuation := AttenuationSlider.Value;
end;

{ TSpot1LightMenu ------------------------------------------------------- }

constructor TSpot1LightMenu.Create(AOwner: TComponent; ALight: TSpotLightNode_1);
begin
  inherited Create(AOwner, ALight);
  Light := ALight;

  CutOffAngleSlider := TCastleFloatSlider.Create(Self);
  CutOffAngleSlider.Min := 0.01;
  CutOffAngleSlider.Max := Pi/2;
  CutOffAngleSlider.Value := Light.FdCutOffAngle.Value;
  CutOffAngleSlider.OnChange := @CutOffAngleChanged;

  DropOffRateSlider := TCastleFloatSlider.Create(Self);
  DropOffRateSlider.Min := 0;
  DropOffRateSlider.Max := 1;
  DropOffRateSlider.Value := Light.FdDropOffRate.Value;
  DropOffRateSlider.OnChange := @DropOffRateChanged;

  Add('Direction ...', @ClickDirection);
  Add('Cut Off Angle', CutOffAngleSlider);
  Add('Drop Off Rate', DropOffRateSlider);
end;

procedure TSpot1LightMenu.ClickDirection(Sender: TObject);
var
  Vector: TVector3Single;
begin
  Vector := Light.ProjectionSceneDirection;
  if MessageInputQueryDirection(Window, 'Change direction' +nl+
    '(Input "C" to use current camera''s direction)',
    Vector) then
    Light.ProjectionSceneDirection := Vector;
end;

procedure TSpot1LightMenu.CutOffAngleChanged(Sender: TObject);
begin
  Light.FdCutOffAngle.Send(CutOffAngleSlider.Value);
end;

procedure TSpot1LightMenu.DropOffRateChanged(Sender: TObject);
begin
  Light.FdDropOffRate.Send(DropOffRateSlider.Value);
end;

{ TSpotLightMenu ------------------------------------------------------- }

constructor TSpotLightMenu.Create(AOwner: TComponent; ALight: TSpotLightNode);
begin
  inherited Create(AOwner, ALight);
  Light := ALight;

  CutOffAngleSlider := TCastleFloatSlider.Create(Self);
  CutOffAngleSlider.Min := 0.01;
  CutOffAngleSlider.Max := Pi/2;
  CutOffAngleSlider.Value := Light.FdCutOffAngle.Value;
  CutOffAngleSlider.OnChange := @CutOffAngleChanged;

  BeamWidthSlider := TCastleFloatSlider.Create(Self);
  BeamWidthSlider.Min := 0.01;
  BeamWidthSlider.Max := Pi/2;
  BeamWidthSlider.Value := Light.FdBeamWidth.Value;
  BeamWidthSlider.OnChange := @BeamWidthChanged;

  Add('Direction ...', @ClickDirection);
  Add('Cut Off Angle', CutOffAngleSlider);
  Add('Beam Width', BeamWidthSlider);
end;

procedure TSpotLightMenu.ClickDirection(Sender: TObject);
var
  Vector: TVector3Single;
begin
  Vector := Light.ProjectionSceneDirection;
  if MessageInputQueryDirection(Window, 'Change direction' +nl+
    '(Input "C" to use current camera''s direction)',
    Vector) then
    Light.ProjectionSceneDirection := Vector;
end;

procedure TSpotLightMenu.CutOffAngleChanged(Sender: TObject);
begin
  Light.CutOffAngle := CutOffAngleSlider.Value;
end;

procedure TSpotLightMenu.BeamWidthChanged(Sender: TObject);
begin
  Light.BeamWidth := BeamWidthSlider.Value;
end;

{ TDirectionalLightMenu ------------------------------------------------------- }

constructor TDirectionalLightMenu.Create(AOwner: TComponent; ALight: TAbstractDirectionalLightNode);
begin
  inherited Create(AOwner, ALight);
  Light := ALight;
  Add('Direction ...', @ClickDirection);
end;

procedure TDirectionalLightMenu.ClickDirection(Sender: TObject);
var
  Vector: TVector3Single;
begin
  Vector := Light.ProjectionSceneDirection;
  if MessageInputQueryDirection(Window, 'Change direction' +nl+
    '(Input "C" to use current camera''s direction)',
    Vector) then
    Light.ProjectionSceneDirection := Vector;
end;

{ THeadLightMenu --------------------------------------------------------- }

constructor THeadLightMenu.Create(AOwner: TComponent; AHeadlight: TAbstractLightNode);
begin
  inherited Create(AOwner);
  Headlight := AHeadlight;

  AddTitle('Headlight:');

  AmbientIntensitySlider := TCastleFloatSlider.Create(Self);
  AmbientIntensitySlider.Min := 0;
  AmbientIntensitySlider.Max := 1;
  AmbientIntensitySlider.Value := Headlight.FdAmbientIntensity.Value;
  AmbientIntensitySlider.OnChange := @AmbientIntensityChanged;
  Add('Ambient Intensity', AmbientIntensitySlider);

  ColorSlider := TMenuVector3Sliders.Create(Self, 0, 1, Headlight.FdColor.Value);
  ColorSlider.OnChange := @ColorChanged;
  ColorSlider.AddToMenu(Self, '', 'Red', 'Green', 'Blue');

  IntensitySlider := TCastleFloatSlider.Create(Self);
  IntensitySlider.Min := 0;
  IntensitySlider.Max := 1;
  IntensitySlider.Value := Headlight.FdIntensity.Value;
  IntensitySlider.OnChange := @IntensityChanged;
  Add('Intensity', IntensitySlider);

  if Headlight is TAbstractPositionalLightNode then
  begin
    { This was a nice message about attenuation for headlight,
      but we have nowhere to place it now:
      MessageOk(Window, 'HeadLight is not positional, it is not possible to set attenuation.' +NL+ NL+
        'To use this function, you need to use our KambiNavigationInfo.headlightNode extension inside your VRML/X3D scene source, to indicate that you want headlight to be a PointLight or SpotLight. See the documentation of VRML/X3D extensions in "Castle Game Engine" for examples and details.'); }

    AttenuationSlider := TMenuVector3Sliders.Create(Self, AttenuationRange,
      TAbstractPositionalLightNode(Headlight).FdAttenuation.Value);
    AttenuationSlider.OnChange := @AttenuationChanged;
    AttenuationSlider.AddToMenu(Self, 'Attenuation', 'Constant' , 'Linear', 'Quadratic');
  end;

  Add('Back to Lights Menu', @ClickBack);
end;

procedure THeadLightMenu.ClickBack(Sender: TObject);
begin
  SetCurrentMenu(LightsMenu);
end;

procedure THeadLightMenu.ColorChanged(Sender: TObject);
begin
  Headlight.Color := ColorSlider.Value;
end;

procedure THeadLightMenu.AttenuationChanged(Sender: TObject);
begin
  (Headlight as TAbstractPositionalLightNode).Attenuation := AttenuationSlider.Value;
end;

procedure THeadLightMenu.AmbientIntensityChanged(Sender: TObject);
begin
  Headlight.AmbientIntensity := AmbientIntensitySlider.Value;
end;

procedure THeadLightMenu.IntensityChanged(Sender: TObject);
begin
  Headlight.Intensity := IntensitySlider.Value;
end;

{ TCastle2ExponentSlider ----------------------------------------------------- }

function TCastle2ExponentSlider.ValueToStr(const AValue: Integer): string;
begin
  Result := IntToStr(2 shl (AValue - 1));
end;

{ TShadowsMenu --------------------------------------------------------------- }

constructor TShadowsMenu.Create(AOwner: TComponent; ALight: TAbstractLightNode);
begin
  inherited Create(AOwner);
  Light := ALight;

  ShadowsToggle := TCastleMenuToggle.Create(Self);
  ShadowsToggle.Pressed := Light.FdShadows.Value;
  ShadowsToggle.OnClick := @ClickShadows;

  ShadowVolumesToggle := TCastleMenuToggle.Create(Self);
  ShadowVolumesToggle.Pressed := Light.FdShadowVolumes.Value;
  ShadowVolumesToggle.OnClick := @ClickShadowVolumes;

  ShadowVolumesMainToggle := TCastleMenuToggle.Create(Self);
  ShadowVolumesMainToggle.Pressed := Light.FdShadowVolumesMain.Value;
  ShadowVolumesMainToggle.OnClick := @ClickShadowVolumesMain;

  SliderMapSizeExponent := TCastle2ExponentSlider.Create(Self);
  SliderMapSizeExponent.Min := 4;
  SliderMapSizeExponent.Max := 13;
  SliderMapSizeExponent.Value := MapSizeExponent;
  SliderMapSizeExponent.OnChange := @MapSizeExponentChanged;

  SliderMapBias := TCastleFloatSlider.Create(Self);
  SliderMapBias.Min := 0.0;
  SliderMapBias.Max := 10.0;
  SliderMapBias.Value := MapBias;
  SliderMapBias.OnChange := @MapBiasChanged;

  SliderMapScale := TCastleFloatSlider.Create(Self);
  SliderMapScale.Min := 0.0;
  SliderMapScale.Max := 10.0;
  SliderMapScale.Value := MapScale;
  SliderMapScale.OnChange := @MapScaleChanged;

  CurrentProjectionLabel := TCastleLabel.Create(Self);

  AddTitle('Edit ' + Light.NiceName + ' -> Shadows Settings:');
  AddTitle('    Shadow Volumes Settings:');
  Add('        Main (Determines Shadows)', ShadowVolumesMainToggle);
  Add('        Off In Shadows', ShadowVolumesToggle);
  AddTitle('    Shadow Maps Settings:');
  Add('        Enable', ShadowsToggle);
  Add('        Map Size', SliderMapSizeExponent);
  Add('        Map Bias (adjust to polygons slope)', SliderMapBias);
  Add('        Map Scale (adjust to polygons slope)', SliderMapScale);
  Add('        Recalculate Projection Parameters', @ClickRecalculateProjection);
  Add(CurrentProjectionLabel);
end;

procedure TShadowsMenu.AfterCreate;
begin
  Add('Back', @ClickBack);

  { We need to call it, to let OnScreenMenu calculate correct size.
    But we cannot call it from constructor,
    as it's virtual and may use Light in descendants, which was unset
    in constructor. }
  UpdateCurrentProjectionLabel(CurrentProjectionLabel);
end;

procedure TShadowsMenu.ClickShadows(Sender: TObject);
begin
  if (Light is TPointLightNode_1) or
     (Light is TPointLightNode) then
  begin
    MessageOK(Window, 'Shadow maps on point lights are not supported yet. Please speak up on "Castle Game Engine" forum and encourage Michalis to implement them, if you want! :) In the meantime, shadow maps work perfectly on other lights (spot and directional).');
    Exit;
  end;

  ShadowsToggle.Pressed := not ShadowsToggle.Pressed;
  Light.Shadows := ShadowsToggle.Pressed;
end;

procedure TShadowsMenu.ClickRecalculateProjection(Sender: TObject);
var
  WasShadows: boolean;
begin
  if (Light is TPointLightNode_1) or
     (Light is TPointLightNode) then
  begin
    MessageOK(Window, 'Shadow maps on point lights are not supported yet. Please speak up on "Castle Game Engine" forum and encourage Michalis to implement them, if you want! :) In the meantime, shadow maps work perfectly on other lights (spot and directional).');
    Exit;
  end;

  WasShadows := Light.Shadows;
  Light.Shadows := false;
  Light.ProjectionNear := 0;
  Light.ProjectionFar := 0;
  if Light is TDirectionalLightNode then
  begin
    TDirectionalLightNode(Light).ProjectionLocationLocal := ZeroVector3Single;
    TDirectionalLightNode(Light).ProjectionRectangle := ZeroVector4Single;
  end;
  Light.Shadows := WasShadows;
end;

procedure TShadowsMenu.ClickShadowVolumes(Sender: TObject);
begin
  ShadowVolumesToggle.Pressed := not ShadowVolumesToggle.Pressed;
  Light.ShadowVolumes := ShadowVolumesToggle.Pressed;
end;

procedure TShadowsMenu.ClickShadowVolumesMain(Sender: TObject);
begin
  ShadowVolumesMainToggle.Pressed := not ShadowVolumesMainToggle.Pressed;
  Light.ShadowVolumesMain := ShadowVolumesMainToggle.Pressed;
end;

procedure TShadowsMenu.ClickBack(Sender: TObject);
begin
  SetCurrentMenu(ParentLightMenu);
end;

function TShadowsMenu.RequiredDefaultShadowMap: TGeneratedShadowMapNode;
begin
  if Light.DefaultShadowMap = nil then
  begin
    Light.DefaultShadowMap := TGeneratedShadowMapNode.Create('', Light.BaseUrl);
    Light.DefaultShadowMap.Scene := Light.Scene;
  end;
  Result := Light.DefaultShadowMap;
end;

function TShadowsMenu.GetMapSizeExponent: Integer;
var
  Sm: TGeneratedShadowMapNode;
begin
  Sm := Light.DefaultShadowMap;
  if Sm <> nil then
    Result := Sm.Size
  else
    Result := TGeneratedShadowMapNode.DefaultSize;
  Result := Biggest2Exponent(Result);
end;

procedure TShadowsMenu.SetMapSizeExponent(const Value: Integer);
var
  Sm: TGeneratedShadowMapNode;
begin
  if Value <> GetMapSizeExponent then
  begin
    Sm := RequiredDefaultShadowMap;
    Sm.Size := 2 shl (Value - 1);
  end;
end;

function TShadowsMenu.GetMapBias: Single;
var
  Sm: TGeneratedShadowMapNode;
begin
  Sm := Light.DefaultShadowMap;
  if Sm <> nil then
    Result := Sm.Bias
  else
    Result := TGeneratedShadowMapNode.DefaultBias;
end;

procedure TShadowsMenu.SetMapBias(const Value: Single);
var
  Sm: TGeneratedShadowMapNode;
begin
  if Value <> GetMapBias then
  begin
    Sm := RequiredDefaultShadowMap;
    Sm.Bias := Value;
  end;
end;

function TShadowsMenu.GetMapScale: Single;
var
  Sm: TGeneratedShadowMapNode;
begin
  Sm := Light.DefaultShadowMap;
  if Sm <> nil then
    Result := Sm.Scale
  else
    Result := TGeneratedShadowMapNode.DefaultScale;
end;

procedure TShadowsMenu.SetMapScale(const Value: Single);
var
  Sm: TGeneratedShadowMapNode;
begin
  if Value <> GetMapScale then
  begin
    Sm := RequiredDefaultShadowMap;
    Sm.Scale := Value;
  end;
end;

procedure TShadowsMenu.MapSizeExponentChanged(Sender: TObject);
begin
  MapSizeExponent := SliderMapSizeExponent.Value;
end;

procedure TShadowsMenu.MapBiasChanged(Sender: TObject);
begin
  MapBias := SliderMapBias.Value;
end;

procedure TShadowsMenu.MapScaleChanged(Sender: TObject);
begin
  MapScale := SliderMapScale.Value;
end;

procedure TShadowsMenu.Update(const SecondsPassed: Single;
  var HandleInput: boolean);
begin
  inherited;
  { Let ParentLightMenu to update Gizmo, in case light moves.
    Note that DirectionalLight.projectionLocation also may change
    when turning on shadows. }
  ParentLightMenu.UpdateLightLocation;
  UpdateCurrentProjectionLabel(CurrentProjectionLabel);
end;

procedure TShadowsMenu.UpdateCurrentProjectionLabel(const ALabel: TCastleLabel);
begin
  ALabel.Text.Clear;
  ALabel.Text.Add('        Currently used projection for shadow maps:');
  ALabel.Text.Add(Format('          Near: %f', [Light.ProjectionNear]));
  ALabel.Text.Add(Format('          Far: %f', [Light.ProjectionFar]));
end;

{ TSpotLightShadowsMenu ------------------------------------------------------- }

constructor TSpotLightShadowsMenu.Create(
  AOwner: TComponent; ALight: TSpotLightNode);
begin
  inherited Create(AOwner, ALight);
  Light := ALight;
end;

procedure TSpotLightShadowsMenu.UpdateCurrentProjectionLabel(
  const ALabel: TCastleLabel);
begin
  inherited;
  ALabel.Text.Add(Format('          Angle: %f', [Light.ProjectionAngle]));
end;

{ TDirectionalLightShadowsMenu ------------------------------------------------------- }

constructor TDirectionalLightShadowsMenu.Create(
  AOwner: TComponent; ALight: TAbstractDirectionalLightNode);
begin
  inherited Create(AOwner, ALight);
  Light := ALight;
end;

procedure TDirectionalLightShadowsMenu.UpdateCurrentProjectionLabel(
  const ALabel: TCastleLabel);
var
  ProjectionRectangle: TFloatRectangle;
begin
  inherited;
  ALabel.Text.Add(Format('          Location: %s',
    [VectorToNiceStr(Light.ProjectionLocation)]));
  ProjectionRectangle := TFloatRectangle.FromX3DVector(Light.ProjectionRectangle);
  ALabel.Text.Add(Format('          Rectangle: %fx%f %fx%f',
    [ProjectionRectangle.Left,
     ProjectionRectangle.Bottom,
     ProjectionRectangle.Width,
     ProjectionRectangle.Height]));
end;

finalization
  { free if it exists at the end }
  FreeAndNil(LightsMenu);
end.
