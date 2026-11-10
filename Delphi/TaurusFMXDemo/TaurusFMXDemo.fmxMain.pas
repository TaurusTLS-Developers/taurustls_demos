/// <summary>Main FMX shell connecting user commands, the download manager and snapshot-based session views.</summary>
unit TaurusFMXDemo.fmxMain;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes, System.Actions, System.IOUtils,
  FMX.Edit, FMX.ActnList, FMX.Dialogs, FMX.Types, FMX.Controls, FMX.Forms, FMX.TabControl,
  TaurusFMXDemo.frmLoader, TaurusFMXDemo.frmDownloadSession,
  TaurusFMXDemo.dmDownload, FMX.Controls.Presentation, FMX.StdCtrls,
  FMX.ListBox, FMX.Layouts, FMX.Objects;

type
  /// <summary>Owns the download manager and designer-based Loader/download presentation.</summary>
  /// <remarks>All methods run on the UI thread. The manager owns workers; list items own only session frames. Workers never receive references to these controls.</remarks>
  TfmxMain = class(TForm)
    MainTabs: TTabControl;
    pnlRequirements: TPanel;
    lblRequirements: TLabel;
    rectRequirementsTint: TRectangle;
    rectRequirementsAccent: TRectangle;
    RequirementsHeader: TLayout;
    lblRequirementsTitle: TLabel;
    btnRequirementsToggle: TButton;
    pathRequirementsChevron: TPath;
    tabLoader: TTabItem;
    MainActions: TActionList;
    actDownload: TAction;
    dlgSaveDownload: TSaveDialog;
    tabDownload: TTabItem;
    pnlTop: TPanel;
    TransferOptions: TLayout;
    RootCAOptions: TLayout;
    edtRootCA: TEdit;
    btnRootCA: TEllipsesEditButton;
    dlgRootCA: TOpenDialog;
    chkWindowsStore: TCheckBox;
    AutoLoadOptions: TLayout;
    chkAutoLoad: TCheckBox;
    rbFTPSExplicit: TRadioButton;
    rbFTPSImplicit: TRadioButton;
    lblFTPControl: TLabel;
    lblAddressError: TLabel;
    edtAddress: TEdit;
    btnDownload: TEditButton;
    lstDownloads: TListBox;
    DownloadToolbar: TLayout;
    btnClearFinished: TButton;
    lblDownloadSummary: TLabel;
    actClearFinished: TAction;
    tmrDownloads: TTimer;
    LoaderFrame: TfrmLoader;
    /// <summary>Selects the optional PEM CA bundle used by future requests.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Does not import certificates into the OS store or reconfigure existing sessions.</remarks>
    procedure BrowseRootCA(Sender: TObject);
    /// <summary>Collapses or expands the minimum-version information for this session.</summary>
    procedure ToggleRequirements(Sender: TObject);
    /// <summary>Refreshes address validation and command availability after address or FTPS-mode changes.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure AddressChanged(Sender: TObject);
    /// <summary>Accepts a nonblank text drop as Copy when no request picker or shutdown is active.</summary>
    /// <param name="Operation">Set to Copy for accepted text; otherwise None.</param>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <param name="Data">Drag payload inspected for a nonblank string value.</param>
    /// <param name="Point">Drop or hover position supplied by FMX; not used to interpret the URL.</param>
    /// <remarks>Drag feedback only; does not validate reachability or start a transfer.</remarks>
    procedure AddressDragOver(Sender: TObject; const Data: TDragObject;
      const Point: TPointF; var Operation: TDragOperation);
    /// <summary>Copies trimmed dropped text into the address edit and runs normal syntax validation.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <param name="Data">Drag payload inspected for a nonblank string value.</param>
    /// <param name="Point">Drop or hover position supplied by FMX; not used to interpret the URL.</param>
    /// <remarks>Files/nontext are ignored. Dropping an address never invokes Download automatically.</remarks>
    procedure AddressDragDrop(Sender: TObject; const Data: TDragObject;
      const Point: TPointF);
    /// <summary>Refreshes the active view and focuses the address only when the Downloads tab is selected.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure FormShow(Sender: TObject);
    /// <summary>Routes Enter through the same validated action used by the Download button.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <param name="Key">Virtual key; Enter is consumed after handling.</param>
    /// <param name="KeyChar">Character value, cleared when Enter is handled.</param>
    /// <param name="Shift">Modifier state supplied by FMX.</param>
    /// <remarks>Consumes Enter before updating and conditionally executing the action.</remarks>
    procedure AddressKeyDown(Sender: TObject; var Key: Word;
      var KeyChar: WideChar; Shift: TShiftState);
    /// <summary>Copies current request settings, obtains Save As approval and starts a managed worker.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Guards modal-dialog reentrancy. Cancel creates no worker; overwrite approval is captured at picker acceptance. Startup exceptions are displayed to the user.</remarks>
    procedure DownloadExecute(Sender: TObject);
    /// <summary>Updates syntax feedback, FTPS-mode availability, effective control port and Download availability.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Performs no network I/O. Invalid addresses do not start a request.</remarks>
    procedure DownloadUpdate(Sender: TObject);
    /// <summary>Asks the embedded Loader frame to refresh when its tab is active.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure RefreshActiveTab(Sender: TObject);
    /// <summary>Polls sessions on the timer and retries closing after all workers have been reaped.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure PollDownloads(Sender: TObject);
    /// <summary>Removes all finished manager entries and refreshes their presentation.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Preserves active workers and downloaded destination files.</remarks>
    procedure ClearFinishedExecute(Sender: TObject);
    /// <summary>Enables bulk cleanup when finished entries exist and no start or close is in progress.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure ClearFinishedUpdate(Sender: TObject);
    /// <summary>Begins cooperative shutdown and defers form closure while workers need cleanup.</summary>
    /// <param name="CanClose">False while Save As is active or unreaped workers remain.</param>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>Rejects new work, requests cancellation and retains timer/form lifetime until polling observes no active workers. Does not pump messages or forcefully terminate threads.</remarks>
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnRootCATap(Sender: TObject; const Point: TPointF);
  private
    FDownloadManager: TDownloadManager;
    FStartingDownload: Boolean;
    FRefreshingDownloads: Boolean;
    FClosingDownloads: Boolean;
    FHasFinished: Boolean;
    FRequirementsCollapsed: Boolean;
    procedure UpdateRequirementsLayout;
    /// <summary>Reconciles copied manager sessions with list frames and updates summary and Loader cover.</summary>
    /// <remarks>ReadSessions also reaps finished workers. Reentrancy is guarded; frames receive values and stable IDs, never worker ownership.</remarks>
    procedure RefreshDownloads;
    /// <summary>Forwards a session frame's stable ID to the manager's cooperative cancellation request.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    procedure CancelSession(Sender: TObject);
    /// <summary>Removes one finished result by ID without deleting its downloaded file.</summary>
    /// <param name="Sender">Event source; ownership remains with its component owner.</param>
    /// <remarks>The next timer tick removes the frame, avoiding destruction inside its own button event.</remarks>
    procedure ClearSession(Sender: TObject);
  public
    /// <summary>Stops polling and frees the manager before inherited control destruction.</summary>
    /// <remarks>Normal close already reaped workers; the manager's fallback destructor can block while joining remaining workers.</remarks>
    destructor Destroy; override;
  protected
    /// <summary>Initializes the streamed Loader frame, target-specific controls, manager and polling timer.</summary>
    procedure DoCreate; override;
    procedure Resize; override;
    /// <summary>Keeps Android content clear of system bars and display cutouts.</summary>
    procedure DoSafeAreaChanged(const AWindowInsets: TRectF); override;
   // for debugging only
   /// <summary>Runs the reusable transfer operation synchronously for development experiments.</summary>
   /// <param name="AURL">Remote address to download.</param>
   /// <param name="ADest">Local destination; this helper permits replacement.</param>
   /// <remarks>Blocks its caller, is not tracked by the form's manager, and is not the normal responsive GUI path.</remarks>
   procedure ExecBlockingDownload(const AURL, ADest: string);

  end;

var
  fmxMain: TfmxMain;

implementation

uses
  TaurusFMXDemo.dmConnect, IdURI, FMX.Platform;

type
  // Controls own presentation only; the manager remains the sole worker owner.
  TDownloadSessionItem = class(TListBoxItem)
    SessionFrame: TfrmDownloadSession;
  end;

{$R *.fmx}
{$R *.SmXhdpiPh.fmx ANDROID}
{$R *.LgXhdpiPh.fmx ANDROID}

procedure TfmxMain.DoCreate;
begin
  inherited;
  MainTabs.ActiveTab := tabLoader;
  LoaderFrame.InitializeActions;
  {$IFNDEF MSWINDOWS}
  chkWindowsStore.Visible := False;
  {$ENDIF}
  FDownloadManager := TDownloadManager.Create;
  tmrDownloads.Enabled := True;
  Resize;
end;

procedure TfmxMain.UpdateRequirementsLayout;
begin
  if not Assigned(pathRequirementsChevron) then Exit;
  lblRequirements.Visible := not FRequirementsCollapsed;
  if FRequirementsCollapsed then
  begin
    pnlRequirements.Height := 40;
    pathRequirementsChevron.RotationAngle := 0;
  end
  else
  begin
    if ClientWidth < 600 then pnlRequirements.Height := 116
    else pnlRequirements.Height := 84;
    pathRequirementsChevron.RotationAngle := 180;
  end;
end;

procedure TfmxMain.ToggleRequirements(Sender: TObject);
begin
  FRequirementsCollapsed := not FRequirementsCollapsed;
  UpdateRequirementsLayout;
end;

procedure TfmxMain.Resize;
var
  LCompact: Boolean;
begin
  inherited;
  if not Assigned(LoaderFrame) or not Assigned(edtAddress) then Exit;
  LCompact := ClientWidth < 600;
  UpdateRequirementsLayout;
  TransferOptions.BeginUpdate;
  try
    if LCompact then
    begin
      pnlTop.Height := 256;
      TransferOptions.Height := 76;
      lblFTPControl.Align := TAlignLayout.Bottom;
      lblFTPControl.Height := 36;
      lblFTPControl.Margins.Left := 0;
      rbFTPSExplicit.Width := 150;
      rbFTPSImplicit.Width := 130;
      lblAddressError.Height := 32;
    end
    else
    begin
      pnlTop.Height := 204;
      TransferOptions.Height := 36;
      lblFTPControl.Align := TAlignLayout.Client;
      lblFTPControl.Margins.Left := 12;
      rbFTPSExplicit.Width := 150;
      rbFTPSImplicit.Width := 150;
      lblAddressError.Height := 20;
    end;
  finally
    TransferOptions.EndUpdate;
  end;
end;

procedure TfmxMain.DoSafeAreaChanged(const AWindowInsets: TRectF);
begin
  inherited;
  {$IFDEF ANDROID}
  // Insets are supplied by FMX in logical coordinates. Replace, do not accumulate:
  // rotation and changes to the system bars can deliver this event repeatedly.
  if Assigned(MainTabs) then
  begin
    // Both the banner and tabs belong inside the same Android safe area.
    Padding.Rect := AWindowInsets;
    MainTabs.Margins.Rect := TRectF.Empty;
  end;
  {$ENDIF}
end;

procedure TfmxMain.FormShow(Sender: TObject);
{$IFDEF ANDROID}
var
  LSafeArea: IFMXWindowSafeAreaService;
{$ENDIF}
begin
  {$IFDEF ANDROID}
  // Also query on show in case the initial notification preceded form streaming.
  if TPlatformServices.Current.SupportsPlatformService(
    IFMXWindowSafeAreaService, LSafeArea) then
    DoSafeAreaChanged(LSafeArea.GetSafeAreaInsets(Self));
  {$ENDIF}
  RefreshActiveTab(Sender);
  if MainTabs.ActiveTab = tabDownload then
    edtAddress.SetFocus;
end;

procedure TfmxMain.AddressKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
    KeyChar := #0;
    actDownload.Update;
    if actDownload.Enabled then
      actDownload.Execute;
  end;
end;

procedure TfmxMain.AddressChanged(Sender: TObject);
begin
  actDownload.Update;
end;

procedure TfmxMain.AddressDragOver(Sender: TObject; const Data: TDragObject;
  const Point: TPointF; var Operation: TDragOperation);
begin
  Operation := TDragOperation.None;
  if not FClosingDownloads and not FStartingDownload and
    Data.Data.IsType<string> and (Trim(Data.Data.AsString) <> '') then
    Operation := TDragOperation.Copy;
end;

procedure TfmxMain.AddressDragDrop(Sender: TObject; const Data: TDragObject;
  const Point: TPointF);
begin
  if FClosingDownloads or FStartingDownload or not Data.Data.IsType<string> then
    Exit;
  if Trim(Data.Data.AsString) = '' then
    Exit;
  edtAddress.Text := Trim(Data.Data.AsString);
  actDownload.Update;
end;

procedure TfmxMain.DownloadUpdate(Sender: TObject);
var
  LError: string;
  LValid: Boolean;
  LURI: TIdURI;
  LPort: string;
begin
  LError := '';
  LValid := Assigned(dmConnect) and
    dmConnect.ValidateDownloadURL(edtAddress.Text, LError);
  // Assign availability once per update; toggling False/True every idle cycle
  // interrupts interaction with an open selector.
  rbFTPSExplicit.Enabled := LValid and
    SameText(Copy(Trim(edtAddress.Text), 1, 5), 'ftps:');
  rbFTPSImplicit.Enabled := rbFTPSExplicit.Enabled;
  lblFTPControl.Text := '';
  if LValid then
  begin
    LURI := TIdURI.Create(Trim(edtAddress.Text));
    try
      if SameText(LURI.Protocol, 'ftp') or SameText(LURI.Protocol, 'ftps') then
      begin
        LPort := LURI.Port;
        if LPort = '' then
          if rbFTPSImplicit.Enabled and rbFTPSImplicit.IsChecked then
            LPort := '990'
          else
            LPort := '21';
        lblFTPControl.Text := 'FTP control port: ' + LPort;
      end;
    finally
      LURI.Free;
    end;
  end;
  actDownload.Enabled := LValid and Assigned(FDownloadManager) and
    not FStartingDownload and not FClosingDownloads;
  lblAddressError.Text := LError;
  if (Trim(edtAddress.Text) <> '') and not LValid then
  begin
    edtAddress.StyledSettings := edtAddress.StyledSettings -
      [TStyledSetting.FontColor];
    edtAddress.TextSettings.FontColor := TAlphaColor($FFB3261E);
    lblAddressError.TextSettings.FontColor := TAlphaColor($FFB3261E);
  end
  else
  begin
    edtAddress.StyledSettings := edtAddress.StyledSettings +
      [TStyledSetting.FontColor];
    lblAddressError.Text := '';
  end;
end;

// this method is for debugging only.
procedure TfmxMain.ExecBlockingDownload(const AURL, ADest: string);
begin
  var LRequest := Default(TDownloadRequest);
  LRequest.URL:=AURL;
  LRequest.Destination:=ADest;
  LRequest.AllowOverwrite:=True;
  LRequest.FTPSMode:=TDownloadFTPSMode.dfExplicitTLS;
  var lOp:=TDownloadManager.CreateDownload(LRequest);
  try
    lOp.Run;
  finally
    lOp.Free;
  end;
end;

procedure TfmxMain.BrowseRootCA(Sender: TObject);
begin
  dlgRootCA.FileName := edtRootCA.Text;
  if dlgRootCA.Execute then
    edtRootCA.Text := dlgRootCA.FileName;
end;

procedure TfmxMain.btnRootCATap(Sender: TObject; const Point: TPointF);
begin
  BrowseRootCA(Sender);
end;

procedure TfmxMain.DownloadExecute(Sender: TObject);
var
  LRequest: TDownloadRequest;
begin
  // Guard the handler itself as well as the action: a native Save As dialog
  // processes messages and must not permit a second invocation or form teardown.
  if FStartingDownload or FClosingDownloads or not Assigned(FDownloadManager) then
    Exit;
  actDownload.Update;
  if not actDownload.Enabled then
    Exit;
  FStartingDownload := True;
  actDownload.Enabled := False;
  try
    // README: normal presentation workflow. Freeze all inputs before Save As
    // processes messages; workers consume this value, never the GUI controls.
    LRequest := Default(TDownloadRequest);
    LRequest.URL := edtAddress.Text;
    LRequest.RootCAFile := Trim(edtRootCA.Text);
    LRequest.AutoLoad := chkAutoLoad.IsChecked;
    {$IFDEF MSWINDOWS}
    LRequest.UseWindowsCertificateStore := chkWindowsStore.IsChecked;
    {$ENDIF}
    if rbFTPSImplicit.IsChecked then
      LRequest.FTPSMode := dfImplicitTLS
    else
      LRequest.FTPSMode := dfExplicitTLS;
    dlgSaveDownload.FileName := dmConnect.SuggestDownloadFilename(LRequest.URL);
    if not dlgSaveDownload.Execute then
      Exit;
    LRequest.Destination := dlgSaveDownload.FileName;
    // Save As prompted for an existing target. If it was absent at acceptance,
    // refuse replacement should a file appear later during this transfer.
    LRequest.AllowOverwrite := TFile.Exists(LRequest.Destination);
    try
      LoaderFrame.CloseUnloadCover(Self);
      FDownloadManager.StartDownload(LRequest);
      RefreshDownloads;
    except
      on E: Exception do
        ShowMessage(E.ClassName + ': ' + E.Message);
    end;
  finally
    FStartingDownload := False;
    actDownload.Update;
  end;
end;

destructor TfmxMain.Destroy;
begin
  if Assigned(tmrDownloads) then
    tmrDownloads.Enabled := False;
  // Normal close has already drained the manager. Its destructor still joins
  // workers as a fallback for exceptional/programmatic form destruction.
  FDownloadManager.Free;
  inherited;
end;

procedure TfmxMain.RefreshDownloads;
var
  LSessions: TArray<TDownloadSessionSnapshot>;
  LSession: TDownloadSessionSnapshot;
  LItem: TDownloadSessionItem;
  I, J, LFinished: Integer;
  LFound: Boolean;
begin
  if not Assigned(FDownloadManager) or FRefreshingDownloads then
    Exit;
  FRefreshingDownloads := True;
  try
    // README: ownership and transfer lifecycle. ReadSessions also reaps finished
    // workers; the list below receives values and never owns a network worker.
    LSessions := FDownloadManager.ReadSessions;
    LFinished := 0;
    lstDownloads.BeginUpdate;
    try
      // Remove presentation only after the manager has removed a retained entry.
      for I := lstDownloads.Count - 1 downto 0 do
      begin
        LItem := TDownloadSessionItem(lstDownloads.ListItems[I]);
        LFound := False;
        for LSession in LSessions do
          if LSession.ID = LItem.SessionFrame.SessionID then
          begin
            LFound := True;
            Break;
          end;
        if not LFound then
          LItem.Free;
      end;
      for LSession in LSessions do
      begin
        LItem := nil;
        for J := 0 to lstDownloads.Count - 1 do
          if TDownloadSessionItem(lstDownloads.ListItems[J]).
            SessionFrame.SessionID = LSession.ID then
          begin
            LItem := TDownloadSessionItem(lstDownloads.ListItems[J]);
            Break;
          end;
        if not Assigned(LItem) then
        begin
          LItem := TDownloadSessionItem.Create(lstDownloads);
          try
            LItem.SessionFrame := TfrmDownloadSession.Create(LItem);
            LItem.SessionFrame.OnCancel := CancelSession;
            LItem.SessionFrame.OnClear := ClearSession;
            LItem.Size.PlatformDefault := False;
            LItem.Height := LItem.SessionFrame.Height;
            LItem.SessionFrame.Align := TAlignLayout.Client;
            LItem.SessionFrame.Parent := LItem;
            LItem.Parent := lstDownloads;
          except
            LItem.Free;
            raise;
          end;
        end;
        LItem.SessionFrame.UpdateSession(LSession);
        if LSession.WorkerFinished then
          Inc(LFinished);
      end;
    finally
      lstDownloads.EndUpdate;
    end;
    FHasFinished := LFinished > 0;
    LoaderFrame.SetActiveDownloads(FDownloadManager.ActiveCount);
    if FClosingDownloads then
      lblDownloadSummary.Text := 'Closing — waiting for ' +
        IntToStr(FDownloadManager.ActiveCount) + ' transfer(s) to finish cleanup…'
    else
      lblDownloadSummary.Text := IntToStr(FDownloadManager.ActiveCount) +
        ' active / ' + IntToStr(LFinished) + ' finished';
  finally
    FRefreshingDownloads := False;
  end;
end;

procedure TfmxMain.PollDownloads(Sender: TObject);
begin
  RefreshDownloads;
  if FClosingDownloads and Assigned(FDownloadManager) and
    (FDownloadManager.ActiveCount = 0) then
  begin
    tmrDownloads.Enabled := False;
    Close;
  end;
end;

procedure TfmxMain.CancelSession(Sender: TObject);
begin
  if Assigned(FDownloadManager) and (Sender is TfrmDownloadSession) then
  begin
    FDownloadManager.Cancel(TfrmDownloadSession(Sender).SessionID);
    RefreshDownloads;
  end;
end;

procedure TfmxMain.ClearSession(Sender: TObject);
begin
  if not Assigned(FDownloadManager) or FClosingDownloads or FStartingDownload or
    not (Sender is TfrmDownloadSession) then
    Exit;
  FDownloadManager.RemoveFinished(TfrmDownloadSession(Sender).SessionID);
  // The next timer poll removes the list item and updates the summary. Do not
  // destroy the sending frame/button while its click handler is still running.
end;

procedure TfmxMain.ClearFinishedExecute(Sender: TObject);
begin
  if not Assigned(FDownloadManager) or FClosingDownloads or FStartingDownload then
    Exit;
  FDownloadManager.ClearFinished;
  RefreshDownloads;
end;

procedure TfmxMain.ClearFinishedUpdate(Sender: TObject);
begin
  actClearFinished.Enabled := FHasFinished and
    not FClosingDownloads and not FStartingDownload;
end;

procedure TfmxMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FStartingDownload;
  if not CanClose or not Assigned(FDownloadManager) then
    Exit;
  // Keep the form, polling timer and shared loader alive until every worker's
  // native clients and streams have been destroyed on their executing thread.
  FClosingDownloads := True;
  FDownloadManager.BeginShutdown;
  actDownload.Enabled := False;
  edtAddress.Enabled := False;
  RefreshDownloads;
  CanClose := FDownloadManager.ActiveCount = 0;
  tmrDownloads.Enabled := not CanClose;
end;

procedure TfmxMain.RefreshActiveTab(Sender: TObject);
begin
  if Assigned(LoaderFrame) and (MainTabs.ActiveTab = tabLoader) then
    LoaderFrame.PollLoader(Sender);
end;

end.
