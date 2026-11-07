/// <summary>Designer-based view of shared Loader configuration, state and lifecycle experiments.</summary>
unit TaurusFMXDemo.frmLoader;

interface

uses
  System.SysUtils, System.Classes, System.Actions, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Edit,
  FMX.Memo, FMX.ScrollBox, FMX.ActnList,
  TaurusFMXDemo.dmConnect, FMX.Memo.Types, FMX.Controls.Presentation,
  FMX.Layouts, FMX.Dialogs;

type
  /// <summary>Presents Loader snapshots and forwards explicit lifecycle actions to dmConnect.</summary>
  /// <remarks>UI-thread only. The unload cover requires deliberate user intent; it does not protect native consumers from library unloading. Hints and component wiring are stored in the FMX resource.</remarks>
  TfrmLoader = class(TFrame)
    lblVersion: TLabel;
    lblState: TLabel;
    lblLibraryPath: TLabel;
    lblConfigFile: TLabel;
    lblSuffixes: TLabel;
    lblEngines: TLabel;
    lblModules: TLabel;
    edtVersion: TEdit;
    edtState: TEdit;
    edtLibraryPath: TEdit;
    edtConfigFile: TEdit;
    edtSuffixes: TEdit;
    edtEngines: TEdit;
    edtModules: TEdit;
    memDesign: TMemo;
    memStatus: TMemo;
    btnToggle: TButton;
    btnUnloadCover: TButton;
    btnCloseCover: TButton;
    LoaderActions: TActionList;
    actToggleLoader: TAction;
    actEditConfig: TAction;
    actEditLibraries: TAction;
    LoaderScroll: TScrollBox;
    grpConfiguration: TGroupBox;
    grpRuntime: TGroupBox;
    btnLibraryPath: TEditButton;
    btnConfigFile: TEditButton;
    dlgConfigFile: TOpenDialog;
    /// <summary>Offers a directory picker for the pending dynamic-library search path.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Rechecks action availability after the dialog; selection does not load OpenSSL.</remarks>
    procedure BrowseLibraryPath(Sender: TObject);
    /// <summary>Offers a file picker for the pending OpenSSL configuration filename.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Cancel preserves the edit; acceptance changes pending text only.</remarks>
    procedure BrowseConfigFile(Sender: TObject);
    /// <summary>Enables configuration editing only while the shared loader is inactive and this controller is not busy.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure UpdateEditConfig(Sender: TObject);
    /// <summary>Enables library-path and suffix editing only for inactive, nonbusy dynamic targets.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure UpdateEditLibraries(Sender: TObject);
    /// <summary>Refreshes the view when dmConnect exists and is not being destroyed.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Used by action updates and explicit host refreshes; never initializes OpenSSL.</remarks>
    procedure PollLoader(Sender: TObject);
    /// <summary>Loads pending settings when inactive, or unloads/resets the shared runtime otherwise.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Active-download unload requires an open cover, including nonmouse invocation. Reports caught exceptions in the lifecycle log and refreshes the view afterward.</remarks>
    procedure ToggleLoader(Sender: TObject);
    /// <summary>Arms deliberate unloading and exposes the lifecycle button while transfers are active.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Opening the cover itself neither unloads the runtime nor cancels transfers.</remarks>
    procedure OpenUnloadCover(Sender: TObject);
    /// <summary>Disarms the active-transfer unload action and refreshes the cover without changing runtime state.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure CloseUnloadCover(Sender: TObject);
  private
    FInitialized: Boolean;
    FLast: TLoaderSnapshot;
    FActiveDownloads: Integer;
    FUnloadArmed: Boolean;
    /// <summary>Renders metadata, state styling, action captions and unload-cover availability.</summary>
    /// <param name="AForce">True to replace pending configuration edits with current runtime values.</param>
    /// <remarks>Normal polling preserves edits unless their corresponding runtime value changed. Requires a valid dmConnect and a fully streamed frame.</remarks>
    procedure RefreshLoader(AForce: Boolean);
  public
    /// <summary>Connects the streamed configuration edits to their availability actions.</summary>
    /// <remarks>Call after the frame and its controls have been created. Does not create controls or initialize OpenSSL.</remarks>
    procedure InitializeActions;
    /// <summary>Receives the host's latest count of workers still awaiting cleanup.</summary>
    /// <param name="ACount">Nonnegative manager ActiveCount after polling.</param>
    /// <remarks>A count change closes the cover. This copied count is presentation state, not a lock or lifetime lease.</remarks>
    procedure SetActiveDownloads(ACount: Integer);
  end;

implementation

uses
  TaurusTLSLoader;

{$R *.fmx}

procedure TfrmLoader.BrowseLibraryPath(Sender: TObject);
var
  LDirectory: string;
begin
  if not actEditLibraries.Enabled then
    Exit;
  LDirectory := edtLibraryPath.Text;
  if SelectDirectory('Select OpenSSL library directory', '', LDirectory) then
    if actEditLibraries.Enabled then
      edtLibraryPath.Text := LDirectory;
end;

procedure TfrmLoader.BrowseConfigFile(Sender: TObject);
var
  LFilename: string;
begin
  if not actEditConfig.Enabled then
    Exit;
  LFilename := edtConfigFile.Text;
  dlgConfigFile.FileName := LFilename;
  dlgConfigFile.InitialDir := '';
  if LFilename <> '' then
    dlgConfigFile.InitialDir := ExtractFilePath(ExpandFileName(LFilename));
  if dlgConfigFile.Execute then
    if actEditConfig.Enabled then
      edtConfigFile.Text := dlgConfigFile.FileName;
end;

procedure TfrmLoader.InitializeActions;
begin
  edtConfigFile.Action := actEditConfig;
  edtLibraryPath.Action := actEditLibraries;
  edtSuffixes.Action := actEditLibraries;
end;

procedure TfrmLoader.SetActiveDownloads(ACount: Integer);
begin
  // README: unload during an active transfer. This is an intentional-action
  // cover, not a lock on OpenSSL or a guarantee that native objects survive unload.
  // A changed count of active workers closes the cover again.
  if FActiveDownloads <> ACount then
    FUnloadArmed := False;
  FActiveDownloads := ACount;
  PollLoader(Self);
end;

procedure TfrmLoader.OpenUnloadCover(Sender: TObject);
begin
  FUnloadArmed := True;
  PollLoader(Self);
end;

procedure TfrmLoader.CloseUnloadCover(Sender: TObject);
begin
  FUnloadArmed := False;
  PollLoader(Self);
end;

procedure TfrmLoader.UpdateEditConfig(Sender: TObject);
var
  LInfo: TLoaderSnapshot;
begin
  actEditConfig.Enabled := False;
  if not Assigned(dmConnect) then
    Exit;
  if csDestroying in dmConnect.ComponentState then
    Exit;
  LInfo := dmConnect.ReadLoader;
  actEditConfig.Enabled := (LInfo.State = lsNotLoaded) and not LInfo.Busy;
end;

procedure TfrmLoader.UpdateEditLibraries(Sender: TObject);
var
  LInfo: TLoaderSnapshot;
begin
  actEditLibraries.Enabled := False;
  if not Assigned(dmConnect) then
    Exit;
  if csDestroying in dmConnect.ComponentState then
    Exit;
  LInfo := dmConnect.ReadLoader;
  actEditLibraries.Enabled := (LInfo.State = lsNotLoaded) and
    not LInfo.Busy and LInfo.DynamicLinking;
end;

procedure TfrmLoader.PollLoader(Sender: TObject);
begin
  // The DPR creates dmConnect first. Still guard shutdown/destruction here:
  // action updates can occur while the application's components are being freed.
  if Assigned(dmConnect) and not (csDestroying in dmConnect.ComponentState) then
    RefreshLoader(False);
end;

procedure TfrmLoader.RefreshLoader(AForce: Boolean);
var
  LInfo: TLoaderSnapshot;
begin
  LInfo := dmConnect.ReadLoader;
  AForce := AForce or not FInitialized;
  if not FInitialized then
    dmConnect.DescribeDesignSettings(memDesign.Lines);
  edtVersion.Text := LInfo.Version;
  case LInfo.State of
    lsNotLoaded:
      begin
        edtState.Text := 'Not loaded / uninitialized';
        edtState.StyledSettings := edtState.StyledSettings +
          [TStyledSetting.Style, TStyledSetting.FontColor];
      end;
    lsLoadedReady:
      begin
        edtState.Text := 'Ready';
        edtState.StyledSettings := edtState.StyledSettings -
          [TStyledSetting.Style, TStyledSetting.FontColor];
        edtState.TextSettings.Font.Style := [TFontStyle.fsBold];
        edtState.TextSettings.FontColor := TAlphaColor($FF228B22);
      end;
    lsLoadedFailed:
      begin
        edtState.Text := 'Failed - unload / uninitialize to reset';
        edtState.StyledSettings := edtState.StyledSettings -
          [TStyledSetting.Style, TStyledSetting.FontColor];
        edtState.TextSettings.Font.Style := [TFontStyle.fsBold];
        edtState.TextSettings.FontColor := TAlphaColor($FFB3261E);
      end;
  end;
  // The button reflects runtime status; its caption still describes the action.
  if LInfo.State = lsNotLoaded then
    btnToggle.StyledSettings := btnToggle.StyledSettings +
      [TStyledSetting.Style, TStyledSetting.FontColor]
  else
  begin
    btnToggle.StyledSettings := btnToggle.StyledSettings -
      [TStyledSetting.Style, TStyledSetting.FontColor];
    btnToggle.TextSettings.Font.Style := [TFontStyle.fsBold];
    btnToggle.TextSettings.FontColor := edtState.TextSettings.FontColor;
  end;
  // Do not overwrite a user's pending edit on each idle cycle.
  if AForce or (LInfo.OpenSSLPath <> FLast.OpenSSLPath) then
    edtLibraryPath.Text := LInfo.OpenSSLPath;
  if AForce or (LInfo.ConfigFile <> FLast.ConfigFile) then
    edtConfigFile.Text := LInfo.ConfigFile;
  if AForce or (LInfo.SSLLibVersions <> FLast.SSLLibVersions) then
    edtSuffixes.Text := LInfo.SSLLibVersions;
  edtEngines.Text := LInfo.EnginesDirectory;
  edtModules.Text := LInfo.ModulesDirectory;
  if (FActiveDownloads = 0) or (LInfo.State = lsNotLoaded) then
    FUnloadArmed := False;
  btnUnloadCover.Visible := (FActiveDownloads > 0) and
    (LInfo.State <> lsNotLoaded) and not FUnloadArmed;
  btnUnloadCover.Enabled := not LInfo.Busy;
  btnCloseCover.Visible := (FActiveDownloads > 0) and
    (LInfo.State <> lsNotLoaded) and FUnloadArmed;
  btnToggle.Visible := not btnUnloadCover.Visible;
  actToggleLoader.Enabled := not LInfo.Busy;
  if LInfo.DynamicLinking then
  begin
    if LInfo.State = lsNotLoaded then actToggleLoader.Text := 'Load'
    else actToggleLoader.Text := 'Unload';
  end
  else
  begin
    if LInfo.State = lsNotLoaded then actToggleLoader.Text := 'Initialize'
    else actToggleLoader.Text := 'Uninitialize';
  end;
  FLast := LInfo;
  FInitialized := True;
end;

procedure TfrmLoader.ToggleLoader(Sender: TObject);
var
  LInfo: TLoaderSnapshot;
begin
  actToggleLoader.Enabled := False;
  actEditConfig.Enabled := False;
  actEditLibraries.Enabled := False;
  try
    try
      LInfo := dmConnect.ReadLoader;
      if LInfo.State = lsNotLoaded then
      begin
        if dmConnect.LoadOpenSSL(edtLibraryPath.Text, edtConfigFile.Text,
          edtSuffixes.Text) then
          memStatus.Lines.Add('OpenSSL is ready.')
        else
          memStatus.Lines.Add('OpenSSL loading failed. Unload / uninitialize before retrying.');
      end
      else
      begin
        // Guard action execution too, including keyboard/programmatic paths.
        if (FActiveDownloads > 0) and not FUnloadArmed then
          Exit;
        FUnloadArmed := False;
        dmConnect.UnloadOpenSSL;
        memStatus.Lines.Add('OpenSSL loader reset to inactive.');
      end;
    except
      on E: Exception do
        memStatus.Lines.Add(E.ClassName + ': ' + E.Message);
    end;
  finally
    RefreshLoader(True);
  end;
end;

end.
