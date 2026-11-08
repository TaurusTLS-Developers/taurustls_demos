unit TaurusFMXDemo.frmDownloadSession;

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Types, System.UITypes, FMX.Types, FMX.Controls,
  FMX.Forms, FMX.StdCtrls, FMX.Layouts, FMX.Menus, FMX.Memo, FMX.ScrollBox,
  FMX.Memo.Types, FMX.TabControl,
  TaurusFMXDemo.dmDownload, FMX.Controls.Presentation, FMX.Objects;

type
  /// <summary>
  ///   Presentation of one session; owns no worker or native TLS objects.
  /// </summary>
  TfrmDownloadSession = class(TFrame)
    SessionContent: TLayout;
    btnDetails: TButton;
    pathDetails: TPath;
    DetailsTabs: TTabControl;
    tabTransferLog: TTabItem;
    tabCertificates: TTabItem;
    memTransferLog: TMemo;
    memCertificates: TMemo;
    SessionCommands: TLayout;
    lblURL: TLabel;
    lblFilename: TLabel;
    lblProgress: TLabel;
    barProgress: TProgressBar;
    lblStatus: TLabel;
    btnCancel: TButton;
    progressUnknown: TAniIndicator;
    CopyMenu: TPopupMenu;
    mnuCopyURL: TMenuItem;
    mnuCopyFilename: TMenuItem;
    mnuCopyStatus: TMenuItem;
    procedure DetailsClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure CopyURLClick(Sender: TObject);
    procedure CopyFilenameClick(Sender: TObject);
    procedure CopyStatusClick(Sender: TObject);
    procedure FrameResize(Sender: TObject);
  private
    FSessionID: Int64;
    FURL: string;
    FFilename: string;
    FCancelRequested: Boolean;
    FOnCancel: TNotifyEvent;
    FOnClear: TNotifyEvent;
    FWorkerFinished: Boolean;
    FTransferLog: string;
    FCertificates: string;
    FUpdatingLayout: Boolean;
    procedure UpdateRowHeight;
    procedure RefreshDetails;
    procedure RefreshNames;
    procedure CopyText(const AText: string);
    function ShortenMiddle(ALabel: TLabel; const AText: string): string;
  public
    /// <summary>
    ///   Applies copied values on the UI thread; safe after worker cleanup.
    /// </summary>
    procedure UpdateSession(const ASession: TDownloadSessionSnapshot);
    property SessionID: Int64 read FSessionID;
    /// <summary>
    ///   Sender is this frame; host forwards its SessionID to the manager.
    /// </summary>
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
    /// <summary>
    ///   Requests removal of a finished entry; host defers freeing this frame.
    /// </summary>
    property OnClear: TNotifyEvent read FOnClear write FOnClear;
  end;

implementation

uses
  FMX.Platform, FMX.TextLayout;

{$R *.fmx}

function ByteText(ABytes: Int64): string;
const
  Units: array[0..4] of string = ('B', 'KiB', 'MiB', 'GiB', 'TiB');
var
  LValue: Double;
  LUnit: Integer;
begin
  LValue := ABytes;
  LUnit := 0;
  while (LValue >= 1024) and (LUnit < High(Units)) do
  begin
    LValue := LValue / 1024;
    Inc(LUnit);
  end;
  if LUnit = 0 then
    Result := IntToStr(ABytes) + ' B'
  else
    Result := FormatFloat('0.0', LValue) + ' ' + Units[LUnit];
end;

function TfrmDownloadSession.ShortenMiddle(ALabel: TLabel;
  const AText: string): string;
var
  LLayout: TTextLayout;
  LKeep, LLeft: Integer;
begin
  Result := AText;
  if ALabel.Width <= 0 then
    Exit('');
  // Measure styled text rather than guessing a character count: filenames and
  // URLs use proportional fonts, and a resized list row can have any width.
  LLayout := TTextLayoutManager.DefaultTextLayout.Create;
  try
    LLayout.Font.Assign(ALabel.ResultingTextSettings.Font);
    LLayout.WordWrap := False;
    LLayout.Text := AText;
    if LLayout.TextWidth <= ALabel.Width then
      Exit;
    LKeep := Length(AText);
    repeat
      Dec(LKeep);
      LLeft := (LKeep + 1) div 2;
      Result := Copy(AText, 1, LLeft) + '…' +
        Copy(AText, Length(AText) - (LKeep div 2) + 1, LKeep div 2);
      LLayout.Text := Result;
    until (LKeep = 0) or (LLayout.TextWidth <= ALabel.Width);
  finally
    LLayout.Free;
  end;
end;

procedure TfrmDownloadSession.RefreshNames;
begin
  if not Assigned(lblURL) or not Assigned(lblFilename) then
    Exit;
  lblURL.Text := ShortenMiddle(lblURL, FURL);
  lblFilename.Text := ShortenMiddle(lblFilename, FFilename);
end;

procedure TfrmDownloadSession.FrameResize(Sender: TObject);
begin
  RefreshNames;
  UpdateRowHeight;
end;

procedure TfrmDownloadSession.UpdateSession(
  const ASession: TDownloadSessionSnapshot);
const
  StateText: array[TDownloadState] of string =
    ('Queued', 'Connecting', 'Downloading', 'Completed', 'Cancelled', 'Failed');
var
  LTerminal: Boolean;
  LPercent: Double;
begin
  FSessionID := ASession.ID;
  if (FTransferLog <> ASession.Progress.TransferLog) or
    (FCertificates <> ASession.Progress.CertificateChain) then
  begin
    FTransferLog := ASession.Progress.TransferLog;
    FCertificates := ASession.Progress.CertificateChain;
    if DetailsTabs.Visible then
      RefreshDetails;
  end;
  if (FURL <> ASession.URL) or (FFilename <> ASession.Progress.Destination) then
  begin
    FURL := ASession.URL;
    FFilename := ASession.Progress.Destination;
    RefreshNames;
  end;
  LTerminal := ASession.Progress.State in [dsCompleted, dsCancelled, dsFailed];
  lblStatus.Text := StateText[ASession.Progress.State];
  if ASession.Progress.ErrorText <> '' then
    lblStatus.Text := lblStatus.Text + ': ' + ASession.Progress.ErrorText;
  FWorkerFinished := ASession.WorkerFinished;
  if FWorkerFinished then
  begin
    btnCancel.Text := 'Clear';
    btnCancel.Enabled := Assigned(FOnClear);
  end
  else
  begin
    btnCancel.Text := 'Cancel';
    btnCancel.Enabled := Assigned(FOnCancel) and not FCancelRequested and
      not LTerminal;
  end;
  // Keep the textual state as well as color so the result is unambiguous.
  if ASession.Progress.State in [dsCompleted, dsFailed] then
  begin
    lblStatus.StyledSettings := lblStatus.StyledSettings -
      [TStyledSetting.Style, TStyledSetting.FontColor];
    lblStatus.TextSettings.Font.Style := [TFontStyle.fsBold];
    if ASession.Progress.State = dsCompleted then
      lblStatus.TextSettings.FontColor := TAlphaColor($FF228B22)
    else
      lblStatus.TextSettings.FontColor := TAlphaColor($FFB3261E);
  end
  else
    lblStatus.StyledSettings := lblStatus.StyledSettings +
      [TStyledSetting.Style, TStyledSetting.FontColor];
  progressUnknown.Enabled := not LTerminal and (ASession.Progress.TotalBytes < 0);
  progressUnknown.Visible := progressUnknown.Enabled;
  barProgress.Visible := ASession.Progress.TotalBytes >= 0;
  if ASession.Progress.TotalBytes >= 0 then
  begin
    if ASession.Progress.TotalBytes > 0 then
      LPercent := EnsureRange(100.0 * ASession.Progress.BytesReceived /
        ASession.Progress.TotalBytes, 0.0, 100.0)
    else if ASession.Progress.State = dsCompleted then
      LPercent := 100
    else
      LPercent := 0;
    barProgress.Value := LPercent;
    lblProgress.Text := FormatFloat('0', LPercent) + '% — ' +
      ByteText(ASession.Progress.BytesReceived) + ' / ' +
      ByteText(ASession.Progress.TotalBytes);
  end
  else
    lblProgress.Text := ByteText(ASession.Progress.BytesReceived) +
      ' received / total unknown';
  if FCancelRequested and not LTerminal then
    lblStatus.Text := 'Cancelling…';
  UpdateRowHeight;
end;

procedure TfrmDownloadSession.RefreshDetails;
begin
  if memTransferLog.Text <> FTransferLog then
    memTransferLog.Text := FTransferLog;
  if FCertificates = '' then
    memCertificates.Text := 'No server certificates captured. Plain HTTP/FTP has no TLS certificate chain.'
  else if memCertificates.Text <> FCertificates then
    memCertificates.Text := FCertificates;
end;

procedure TfrmDownloadSession.UpdateRowHeight;
var
  LLayout: TTextLayout;
  LHeight, LCommandsHeight: Single;
begin
  if FUpdatingLayout or (csLoading in ComponentState) or
    not Assigned(lblStatus) or not Assigned(DetailsTabs) or
    not Assigned(btnDetails) or not Assigned(progressUnknown) then
    Exit;
  // README: session presentation owns no transfer state. Resizing the host row
  // re-enters OnResize, so measure/update the view under this recursion guard.
  FUpdatingLayout := True;
  try
    LLayout := TTextLayoutManager.DefaultTextLayout.Create;
    try
      LLayout.Font.Assign(lblStatus.ResultingTextSettings.Font);
      LLayout.MaxSize := TPointF.Create(Max(1, lblStatus.Width), 10000);
      LLayout.WordWrap := True;
      LLayout.Text := lblStatus.Text;
      lblStatus.Height := Max(20, Ceil(LLayout.TextHeight) + 4);
    finally
      LLayout.Free;
    end;
    LHeight := lblURL.Height + lblFilename.Height + lblProgress.Height +
      lblStatus.Height;
    if barProgress.Visible then
      LHeight := LHeight + barProgress.Height;
    LCommandsHeight := btnDetails.Position.Y + btnDetails.Height;
    if progressUnknown.Visible then
      LCommandsHeight := Max(LCommandsHeight,
        progressUnknown.Position.Y + progressUnknown.Height);
    LHeight := Max(LHeight, LCommandsHeight) + Padding.Top + Padding.Bottom;
    if DetailsTabs.Visible then
      LHeight := LHeight + DetailsTabs.Height;
    if Parent is TControl then
    begin
      if not SameValue(TControl(Parent).Height, LHeight, 0.5) then
        TControl(Parent).Height := LHeight;
    end
    else if not SameValue(Height, LHeight, 0.5) then
      Height := LHeight;
  finally
    FUpdatingLayout := False;
  end;
end;

procedure TfrmDownloadSession.DetailsClick(Sender: TObject);
begin
  DetailsTabs.Visible := not DetailsTabs.Visible;
  // A vector image avoids platform font coverage and source encoding differences.
  if DetailsTabs.Visible then
  begin
    RefreshDetails;
    pathDetails.RotationAngle := 180;
  end
  else
    pathDetails.RotationAngle := 0;
  UpdateRowHeight;
end;

procedure TfrmDownloadSession.CancelClick(Sender: TObject);
begin
  if not btnCancel.Enabled then
    Exit;
  if FWorkerFinished then
  begin
    // The host must not free this frame inside its own button event.
    if Assigned(FOnClear) then
    begin
      btnCancel.Enabled := False;
      FOnClear(Self);
    end;
    Exit;
  end;
  if not Assigned(FOnCancel) then
    Exit;
  FCancelRequested := True;
  btnCancel.Enabled := False;
  lblStatus.Text := 'Cancelling…';
  FOnCancel(Self);
end;

procedure TfrmDownloadSession.CopyText(const AText: string);
var
  LClipboard: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService,
    LClipboard) then
    LClipboard.SetClipboard(AText);
end;

procedure TfrmDownloadSession.CopyURLClick(Sender: TObject);
begin
  CopyText(FURL);
end;

procedure TfrmDownloadSession.CopyFilenameClick(Sender: TObject);
begin
  CopyText(FFilename);
end;

procedure TfrmDownloadSession.CopyStatusClick(Sender: TObject);
begin
  CopyText(lblStatus.Text);
end;

end.
