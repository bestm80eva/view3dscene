unit V3DSceneShadows;

interface

uses ShadowVolumes, GLWindow, VRMLGLScene, VectorMath;

var
  MenuShadowsMenu: TMenu;

const
  DefaultShadowsPossibleWanted = true;

var
  { Whether user wants to try next time to initialize
    ShadowsPossibleCurrently = true.
    This can change during runtime, but will be applied only on restart. }
  ShadowsPossibleWanted: boolean = DefaultShadowsPossibleWanted;

  { Whether we managed to initialize OpenGL context with stencil buffer
    (and set projection to infinity and initialized ShadowVolumes instance).
    This can be true only if ShadowsPossibleWanted was initially true. }
  ShadowsPossibleCurrently: boolean = false;

  ShadowsOn: boolean = true;
  DrawShadowVolumes: boolean = false;

procedure ShadowsGLInit;
procedure ShadowsGLClose;
procedure ShadowsRender(Scene: TVRMLGLscene;
  const Frustum: TFrustum; const MainLightPosition: TVector4Single);

implementation

uses SysUtils, V3DSceneConfig;

var
  SV: TShadowVolumes;

procedure ShadowsGLInit;
begin
  if ShadowsPossibleCurrently then
  begin
    SV := TShadowVolumes.Create;
    SV.InitGLContext;
  end;
  MenuShadowsMenu.Enabled := ShadowsPossibleCurrently;
end;

procedure ShadowsGLClose;
begin
  FreeAndNil(SV);
end;

type
  TRenderer = class
    Scene: TVRMLGLScene;
    Frustum: PFrustum;
    procedure RenderScene(InShadow: boolean);
    procedure RenderShadowVolumes;
  end;

procedure TRenderer.RenderScene(InShadow: boolean);
begin
  if InShadow then
    Scene.RenderFrustum(Frustum^, tgAll, @Scene.LightRenderInShadow) else
    Scene.RenderFrustum(Frustum^, tgAll, nil);
end;

procedure TRenderer.RenderShadowVolumes;
begin
  Scene.InitAndRenderShadowVolume(SV, true, IdentityMatrix4Single);
end;

procedure ShadowsRender(Scene: TVRMLGLscene;
  const Frustum: TFrustum; const MainLightPosition: TVector4Single);
var
  R: TRenderer;
begin
  R := TRenderer.Create;
  try
    R.Scene := Scene;
    R.Frustum := @Frustum;

    SV.InitFrustumAndLight(Frustum, MainLightPosition);
    SV.Render(
      nil,
      @R.RenderScene,
      @R.RenderShadowVolumes,
      DrawShadowVolumes);
  finally FreeAndNil(R) end;
end;

initialization
  ShadowsPossibleWanted := ConfigFile.GetValue(
    'video_options/shadows_possible_wanted', DefaultShadowsPossibleWanted);
finalization
  ConfigFile.SetDeleteValue('video_options/shadows_possible_wanted',
    ShadowsPossibleWanted, DefaultShadowsPossibleWanted);
end.