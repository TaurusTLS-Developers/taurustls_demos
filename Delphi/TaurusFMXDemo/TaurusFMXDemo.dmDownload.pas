unit TaurusFMXDemo.dmDownload;

{$IFDEF FPC}
{$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, SyncObjs, System.Generics.Collections, IdCTypes, TaurusTLSHeaders_types,
  TaurusTLS_X509, IdIOHandler, IdIOHandlerSocket, IdIOHandlerStack, IdSSL,
  TaurusTLS, IdExplicitTLSClientServerBase, IdFTP, IdBaseComponent, IdComponent,
  IdTCPConnection, IdTCPClient, IdHTTP, IdHeaderList, IdLogEvent, IdIntercept,
  IdLogBase, IdAllFTPListParsers, TaurusTLS_Unicode_Log;

type
  TDownloadState = (dsQueued, dsConnecting, dsDownloading, dsCompleted,
    dsCancelled, dsFailed);
  TDownloadFTPSMode = (dfExplicitTLS, dfImplicitTLS);

  /// <summary>
  ///   Immutable transfer settings copied by the worker constructor.
  /// </summary>
  /// <remarks>
  ///   Value-initialize before assigning fields. RootCAFile optionally supplies
  ///   trusted CAs; FTPSMode defaults to explicit TLS when zero-initialized.
  /// </remarks>
  TDownloadRequest = record
    URL: string;
    Destination: string;
    AllowOverwrite: Boolean;
    FTPSMode: TDownloadFTPSMode;
    RootCAFile: string;
    UseWindowsCertificateStore: Boolean;
  end;

  /// <summary>
  ///   Thread-safe value snapshot for UI polling, without native object
  ///   references.
  /// </summary>
  /// <remarks>
  ///   TotalBytes is -1 until known. A terminal state is published after
  ///   cleanup; the owner must still join the thread before releasing
  ///   worker-owned resources.
  /// </remarks>
  TDownloadSnapshot = record
    State: TDownloadState;
    Destination: string;
    BytesReceived: Int64;
    TotalBytes: Int64; // -1 means unknown.
    ErrorText: string;
    TransferLog: string;
    CertificateChain: string;
  end;

  TDownloadOperation = class;

  /// <summary>
  ///   Thread-confined Indy clients and one TLS handler for one transfer.
  /// </summary>
  /// <remarks>
  ///   Created, used and freed on the operation's calling thread.
  /// </remarks>
  TdmDownload = class(TDataModule)
    cliHTTP: TIdHTTP;
    cliFTP: TIdFTP;
    iohTLS: TTaurusTLSIOHandlerSocket;
    logFTP: TTaurusTLSUnicodeLog;
    procedure HTTPHeaders(Sender: TObject; AHeaders: TIdHeaderList;
      var VContinue: Boolean);
    procedure FTPReceived(ASender: TComponent; const AData: string);
    procedure FTPSent(ASender: TComponent; const AData: string);
    procedure TLSNegotiated(ASender: TTaurusTLSIOHandlerSocket);
    procedure TLSVerify(ASender: TObject; const APreverify_ok: TIdC_INT;
      ACertificate: TTaurusTLSX509; const ADepth: Integer;
      const AError: TIdC_LONG; const AMsg, ADescr: string; var VContinue: Boolean);
    procedure ClientWork(ASender: TObject; AWorkMode: TWorkMode;
      AWorkCount: Int64);
    procedure HTTPWorkBegin(ASender: TObject; AWorkMode: TWorkMode;
      AWorkCountMax: Int64);
    procedure HTTPRedirect(Sender: TObject; var Dest: string;
      var NumRedirect: Integer; var Handled: Boolean; var VMethod: TIdHTTPMethod);
    procedure DataModuleCreate(Sender: TObject);
  private
    FOperation: TDownloadOperation;
    FFTPCommandBuffer: string;
    procedure OnBeforeBindHandler(ASender: TObject);
    /// <summary>
    ///   Configures the session handler using the current operation request.
    /// </summary>
    procedure ConfigureTLS;
  public
    /// <summary>
    ///   Streams the requested resource to the caller-owned output stream.
    /// </summary>
    /// <remarks>
    ///   Call only on the operation's executing thread. Secure requests require
    ///   an initialized shared loader throughout transfer and native-object
    ///   cleanup. Exceptions propagate.
    /// </remarks>
    procedure Transfer(const ARequest: TDownloadRequest; AOutput: TStream;
      AOperation: TDownloadOperation);
  end;

  /// <summary>
  ///   One transfer, executed on its caller's thread without creating a
  ///   TThread.
  /// </summary>
  /// <remarks>
  ///   Caller owns this object. Run once; Cancel and ReadSnapshot are safe
  ///   during execution. Do not free until Run returns. Run blocks its calling
  ///   thread.
  /// </remarks>
  TDownloadOperation = class
  private
    FRequest: TDownloadRequest;
    FLock: TCriticalSection;
    FSnapshot: TDownloadSnapshot;
    FCancelled: Boolean;
    FStarted: Boolean;
    procedure SetState(AState: TDownloadState; const AError: string = '');
    procedure CheckCancelled;
    procedure ReportBytes(ACount: Integer);
    procedure SetTotal(ATotal: Int64);
    procedure AppendLog(const AText: string);
    procedure AppendCertificates(const AText: string);
    function IsCancelled: Boolean;
  public
    constructor Create(const ARequest: TDownloadRequest);
    destructor Destroy; override;
    /// <summary>
    ///   Runs once on the calling thread; transfer failures enter the snapshot.
    /// </summary>
    procedure Run;
    procedure Cancel;
    function ReadSnapshot: TDownloadSnapshot;
  end;

  /// <summary>
  ///   Thread adapter owning the same operation used for synchronous transfers.
  /// </summary>
  /// <remarks>
  ///   Created suspended, FreeOnTerminate=False. Owner starts, cancels and
  ///   joins it.
  /// </remarks>
  TDownloadWorker = class(TThread)
  private
    FOperation: TDownloadOperation;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARequest: TDownloadRequest);
    destructor Destroy; override;
    procedure Cancel;
    function ReadSnapshot: TDownloadSnapshot;
  end;

  /// <summary>
  ///   Stable identity and copied progress for one retained download entry.
  /// </summary>
  /// <remarks>
  ///   WorkerFinished confirms thread cleanup, independently of terminal State.
  ///   Protocol-specific session information can later extend Progress.
  /// </remarks>
  TDownloadSessionSnapshot = record
    ID: Int64;
    URL: string;
    Progress: TDownloadSnapshot;
    WorkerFinished: Boolean;
  end;

  /// <summary>
  ///   Owns active workers and retained results in one session list.
  /// </summary>
  /// <remarks>
  ///   Call all methods from the creating/UI thread. Workers never access this
  ///   list. Poll during idle/timer updates, including while closing.
  ///   BeginShutdown rejects new work and requests cancellation without
  ///   waiting; destroy only after ActiveCount=0 for responsive shutdown.
  ///   Destroy joins any remaining workers as a safety net and may block on
  ///   DNS/network operations.
  /// </remarks>
  TDownloadManager = class
  private type
    TSession = class
      ID: Int64;
      URL: string;
      Worker: TDownloadWorker;
      Snapshot: TDownloadSnapshot;
      destructor Destroy; override;
    end;
  private
    FSessions: TObjectList<TSession>;
    FNextID: Int64;
    FShuttingDown: Boolean;
    function GetActiveCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    ///   Creates a caller-owned operation for synchronous execution.
    /// </summary>
    /// <remarks>
    ///   No thread is created. Call Run, inspect ReadSnapshot, then Free. Run
    ///   blocks the caller; use a worker for responsive GUI downloads.
    ///   Standalone operations are not tracked by a manager instance.
    /// </remarks>
    class function CreateDownload(const ARequest: TDownloadRequest): TDownloadOperation; static;
    /// <summary>
    ///   Creates and starts a worker; returns its never-reused session ID.
    /// </summary>
    function StartDownload(const ARequest: TDownloadRequest): Int64;
    /// <summary>Refreshes snapshots and joins/frees only finished workers.</summary>
    procedure Poll;
    /// <summary>
    ///   Polls and returns value copies in insertion order.
    /// </summary>
    function ReadSessions: TArray<TDownloadSessionSnapshot>;
    /// <summary>
    ///   Requests cancellation by ID; False means absent or already reaped.
    /// </summary>
    function Cancel(AID: Int64): Boolean;
    /// <summary>
    ///   Removes an entry only after its worker has finished and been reaped.
    /// </summary>
    function RemoveFinished(AID: Int64): Boolean;
    /// <summary>
    ///   Removes all reaped entries, preserving active downloads.
    /// </summary>
    procedure ClearFinished;
    /// <summary>
    ///   Requests cancellation of every worker; does not wait.
    /// </summary>
    procedure CancelAll;
    /// <summary>
    ///   Idempotently prevents new downloads and cancels existing workers.
    /// </summary>
    procedure BeginShutdown;
    /// <summary>
    ///   Unreaped worker count; call Poll to refresh before testing for zero.
    /// </summary>
    property ActiveCount: Integer read GetActiveCount;
    property ShuttingDown: Boolean read FShuttingDown;
  end;

implementation

uses
  IdURI, IdGlobal, IdFTPCommon, TaurusTLSLoader, System.IOUtils,
  TaurusTLSHeaders_ssl, TaurusTLSHeaders_x509;

{$IFDEF FPC}
{$R *.lfm}
{$ELSE}
{%CLASSGROUP 'System.Classes.TPersistent'}
{$R *.dfm}
{$ENDIF}

type
  EDownloadCancelled = class(Exception);

  // Counts actual body bytes written, not FTP control traffic/HTTP headers.
  TDownloadFileStream = class(TFileStream)
  private
    FOperation: TDownloadOperation;
  public
    constructor Create(const AFilename: string; AOperation: TDownloadOperation);
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

var
  TargetLock: TCriticalSection;
  ActiveTargets: TStringList;

constructor TDownloadFileStream.Create(const AFilename: string;
  AOperation: TDownloadOperation);
begin
  inherited Create(AFilename, fmCreate or fmShareExclusive);
  FOperation := AOperation;
end;

function TDownloadFileStream.Write(const Buffer; Count: Longint): Longint;
begin
  FOperation.CheckCancelled;
  Result := inherited Write(Buffer, Count);
  FOperation.ReportBytes(Result);
end;

procedure TdmDownload.HTTPHeaders(Sender: TObject; AHeaders: TIdHeaderList;
  var VContinue: Boolean);
begin
  FOperation.CheckCancelled;
  // Capture here, before Indy processes redirects or rejects an HTTP status,
  // so the transcript includes intermediate and failing responses too.
  FOperation.AppendLog(cliHTTP.Request.Method + ' ' + cliHTTP.URL.URI +
    sLineBreak + cliHTTP.ResponseText + sLineBreak + AHeaders.Text);
end;

procedure TdmDownload.FTPReceived(ASender: TComponent; const AData: string);
begin
  FOperation.AppendLog('< ' + AData);
end;

procedure TdmDownload.FTPSent(ASender: TComponent; const AData: string);
var
  P: Integer;
  LLine: string;
begin
  // Intercept buffers may split commands. Mask credentials only after a whole
  // line is available, and never publish a partially received password.
  FFTPCommandBuffer := FFTPCommandBuffer + AData;
  P := Pos(#10, FFTPCommandBuffer);
  while P > 0 do
  begin
    LLine := TrimRight(Copy(FFTPCommandBuffer, 1, P - 1));
    Delete(FFTPCommandBuffer, 1, P);
    if SameText(Copy(LLine, 1, 5), 'PASS ') or
      SameText(Copy(LLine, 1, 5), 'ACCT ') then
      LLine := Copy(LLine, 1, 4) + ' ********';
    FOperation.AppendLog('> ' + LLine);
    P := Pos(#10, FFTPCommandBuffer);
  end;
end;

procedure TdmDownload.TLSVerify(ASender: TObject; const APreverify_ok: TIdC_INT;
  ACertificate: TTaurusTLSX509; const ADepth: Integer;
  const AError: TIdC_LONG; const AMsg, ADescr: string; var VContinue: Boolean);
begin
  // Observation must never turn a failed OpenSSL verification into acceptance.
  VContinue := VContinue and (APreverify_ok <> 0);
  if Assigned(ACertificate) then
    FOperation.AppendCertificates(Format('Verification depth %d; result %d: %s',
      [ADepth, AError, AMsg]) + sLineBreak + ACertificate.DisplayInfo.Text);
end;

procedure TdmDownload.TLSNegotiated(ASender: TTaurusTLSIOHandlerSocket);
var
  LChain: PSTACK_OF_X509;
  LCertificate: TTaurusTLSX509;
  I: Integer;
  LText: string;
begin
  // Snapshot the server-sent chain while the worker owns the live connection.
  // This differs from the verification path, which can include local trust CAs.
  LText := 'Server-sent certificate chain for ' + ASender.Host + ':' +
    IntToStr(ASender.Port) + sLineBreak;
  LChain := SSL_get_peer_cert_chain(ASender.SSLSocket.SSL);
  if LChain <> nil then
    for I := 0 to sk_X509_num(LChain) - 1 do
    begin
      // OpenSSL owns the stack/certificate. False makes this wrapper borrow it;
      // only DisplayInfo text is retained beyond the callback/connection lifetime.
      LCertificate := TTaurusTLSX509.Create(sk_X509_value(LChain, I), False);
      try
        LText := LText + Format('Certificate %d (leaf first)', [I + 1]) +
          sLineBreak + LCertificate.DisplayInfo.Text + sLineBreak;
      finally
        LCertificate.Free;
      end;
    end
  else
    LText := LText + 'No server chain supplied.' + sLineBreak;
  FOperation.AppendCertificates(LText);
end;

procedure TdmDownload.ClientWork(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCount: Int64);
begin
  FOperation.CheckCancelled;
end;

procedure TdmDownload.HTTPWorkBegin(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCountMax: Int64);
begin
  FOperation.CheckCancelled;
  if AWorkMode = wmRead then
    if AWorkCountMax > 0 then
      FOperation.SetTotal(AWorkCountMax);
end;

procedure TdmDownload.HTTPRedirect(Sender: TObject; var Dest: string;
  var NumRedirect: Integer; var Handled: Boolean; var VMethod: TIdHTTPMethod);
var
  LTarget: TIdURI;
  LProtocol: string;
begin
  FOperation.CheckCancelled;
  FOperation.AppendLog(Format('Redirect %d: %s -> %s',
    [NumRedirect, cliHTTP.URL.URI, Dest]));
  // Indy follows a hop only while NumRedirect < RedirectMaximum (9).
  // Explicitly reject the ninth response, allowing exactly eight followed hops.
  if NumRedirect > 8 then
    raise Exception.Create('HTTP redirect limit (8) exceeded');
  LTarget := TIdURI.Create(Dest);
  try
    LProtocol := LTarget.Protocol;
    // Indy resolves relative Location values against its current URL.
    if LProtocol = '' then
      LProtocol := cliHTTP.URL.Protocol;
    if not SameText(LProtocol, 'http') and not SameText(LProtocol, 'https') then
      raise Exception.Create('HTTP redirect requires an HTTP or HTTPS destination');
    // Start each hop with a fresh connection. This also avoids consuming a
    // redirect body through a handler that is being replaced for HTTP/HTTPS.
    cliHTTP.Disconnect;
    if SameText(LProtocol, 'https') then
    begin
      ConfigureTLS;
      cliHTTP.IOHandler := iohTLS;
    end
    else
      cliHTTP.IOHandler := nil;
    FOperation.SetTotal(-1);
  finally
    LTarget.Free;
  end;
end;

procedure TdmDownload.OnBeforeBindHandler(ASender: TObject);
var
  [unsafe] LLoader: IOpenSSLLoader;
begin
  if ASender is TIdTCPClientCustom then
    Exit;
  LLoader:=GetOpenSSLLoader;
  if not (LLoader.IsLoaded or LLoader.Load) then
    raise Exception.Create('Failed to autoload OpenSSL library');
end;

procedure TdmDownload.ConfigureTLS;
begin
  // README: trust and diagnostics. Apply the request's copied settings before
  // TLS context creation. Selecting trust sources does not initialize OpenSSL.
  iohTLS.SSLOptions.Mode := sslmClient;
  iohTLS.SSLOptions.VerifyMode := [sslvrfPeer];
  iohTLS.SSLOptions.VerifyHostname := True;
  iohTLS.ClientCert.RootKey := FOperation.FRequest.RootCAFile;
  {$IFDEF MSWINDOWS}
  iohTLS.SSLOptions.UseSystemRootCACertificateStore :=
    FOperation.FRequest.UseWindowsCertificateStore;
  {$ENDIF}
end;

procedure TdmDownload.DataModuleCreate(Sender: TObject);
begin
  // Intentionally not assigned to the data module's OnCreate event by default.
  // For the presentation's on-demand OpenSSL loading scenario, assign
  // OnCreate = DataModuleCreate in the Object Inspector before running.
  // This connects both clients to OnBeforeBindHandler; without this
  // wiring, initialize OpenSSL explicitly using the Loader tab.
  cliHTTP.OnBeforeBind:=OnBeforeBindHandler;
  cliFTP.OnBeforeBind:=OnBeforeBindHandler;
end;

procedure TdmDownload.Transfer(const ARequest: TDownloadRequest;
  AOutput: TStream; AOperation: TDownloadOperation);
var
  LURI: TIdURI;
  LSecure, LHTTP: Boolean;
  LPort: Integer;
  LRemoteFile: string;

  function Decode(const AValue: string): string;
  begin
    Result := TIdURI.URLDecode(AValue, IndyTextEncoding_UTF8);
    if (Pos(#0, Result) > 0) or (Pos(#10, Result) > 0) or
      (Pos(#13, Result) > 0) then
      raise Exception.Create('URL contains an invalid control character');
  end;

begin
  FOperation := AOperation;
  FOperation.CheckCancelled;
  LURI := TIdURI.Create(Trim(ARequest.URL));
  try
    LHTTP := SameText(LURI.Protocol, 'http') or SameText(LURI.Protocol, 'https');
    LSecure := SameText(LURI.Protocol, 'https') or SameText(LURI.Protocol, 'ftps');
    if not LHTTP and not SameText(LURI.Protocol, 'ftp') and
      not SameText(LURI.Protocol, 'ftps') then
      raise Exception.Create('Unsupported download protocol');
    if (LURI.Host = '') or (not LHTTP and (LURI.Document = '')) then
      raise Exception.Create('A host is required; FTP also requires a file name');
    // One module serves one transfer. Only the chosen client may use the
    // session handler; plain protocols must not initialize a TLS context.
    if LHTTP then
      cliFTP.IOHandler := nil
    else
      cliHTTP.IOHandler := nil;
    if LSecure then
    begin
      ConfigureTLS;
      if LHTTP then
        cliHTTP.IOHandler := iohTLS
      else
        cliFTP.IOHandler := iohTLS;
    end;
    if LHTTP then
    begin
      if not LSecure then
        cliHTTP.IOHandler := nil;
      cliHTTP.ConnectTimeout := 15000;
      cliHTTP.ReadTimeout := 15000;
      cliHTTP.Get(ARequest.URL, AOutput);
      cliHTTP.Disconnect;
    end
    else
    begin
      if SameText(LURI.Protocol, 'ftps') then
      begin
        if ARequest.FTPSMode = dfImplicitTLS then
          cliFTP.UseTLS := utUseImplicitTLS
        else
          cliFTP.UseTLS := utUseRequireTLS;
        cliFTP.DataPortProtection := ftpdpsPrivate;
      end
      else
      begin
        cliFTP.UseTLS := utNoTLSSupport;
        cliFTP.IOHandler := nil;
      end;
      LPort := 21;
      if LSecure and (ARequest.FTPSMode = dfImplicitTLS) then
        LPort := 990;
      if LURI.Port <> '' then
        if not TryStrToInt(LURI.Port, LPort) then
          raise Exception.Create('Invalid FTP port');
      if (LPort < 1) or (LPort > 65535) then
        raise Exception.Create('Invalid FTP port');
      FOperation.AppendLog(Format('FTP control channel: %s:%d', [LURI.Host, LPort]));
      if not LSecure then
        FOperation.AppendLog('Mode: plain FTP')
      else if ARequest.FTPSMode = dfImplicitTLS then
        FOperation.AppendLog('Mode: implicit FTPS')
      else
        FOperation.AppendLog('Mode: explicit FTPS');
      // The Unicode logger decodes FTP control text as UTF-8.
      cliFTP.Host := LURI.Host;
      cliFTP.Port := LPort;
      cliFTP.Username := Decode(LURI.Username);
      cliFTP.Password := Decode(LURI.Password);
      if cliFTP.Username = '' then
      begin
        cliFTP.Username := 'anonymous';
        cliFTP.Password := 'demo@localhost';
      end;
      LRemoteFile := Decode(LURI.Path + LURI.Document);
      cliFTP.Connect;
      FOperation.CheckCancelled;
      cliFTP.Get(LRemoteFile, AOutput, False);
      cliFTP.Disconnect;
    end;
    FOperation.CheckCancelled;
  finally
    LURI.Free;
  end;
end;

constructor TDownloadOperation.Create(const ARequest: TDownloadRequest);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRequest := ARequest;
  FRequest.URL := Trim(FRequest.URL);
  if Trim(FRequest.Destination) <> '' then
    FRequest.Destination := TPath.GetFullPath(FRequest.Destination);
  FSnapshot.State := dsQueued;
  FSnapshot.Destination := FRequest.Destination;
  FSnapshot.TotalBytes := -1;
end;

destructor TDownloadOperation.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TDownloadOperation.Cancel;
begin
  FLock.Enter;
  try
    FCancelled := True;
  finally
    FLock.Leave;
  end;
end;

function TDownloadOperation.IsCancelled: Boolean;
begin
  FLock.Enter;
  try
    Result := FCancelled;
  finally
    FLock.Leave;
  end;
end;

procedure TDownloadOperation.CheckCancelled;
begin
  if IsCancelled then
    raise EDownloadCancelled.Create('Download cancelled');
end;

function TDownloadOperation.ReadSnapshot: TDownloadSnapshot;
begin
  FLock.Enter;
  try
    Result := FSnapshot;
  finally
    FLock.Leave;
  end;
end;

procedure TDownloadOperation.SetState(AState: TDownloadState; const AError: string);
begin
  FLock.Enter;
  try
    FSnapshot.State := AState;
    FSnapshot.ErrorText := AError;
  finally
    FLock.Leave;
  end;
end;

procedure TDownloadOperation.SetTotal(ATotal: Int64);
begin
  FLock.Enter;
  try
    FSnapshot.TotalBytes := ATotal;
  finally
    FLock.Leave;
  end;
end;

procedure TDownloadOperation.AppendLog(const AText: string);
begin
  FLock.Enter;
  try
    FSnapshot.TransferLog := FSnapshot.TransferLog + AText + sLineBreak;
  finally
    FLock.Leave;
  end;
end;

procedure TDownloadOperation.AppendCertificates(const AText: string);
begin
  FLock.Enter;
  try
    FSnapshot.CertificateChain := FSnapshot.CertificateChain + AText + sLineBreak;
  finally
    FLock.Leave;
  end;
end;

procedure TDownloadOperation.ReportBytes(ACount: Integer);
begin
  FLock.Enter;
  try
    Inc(FSnapshot.BytesReceived, ACount);
    FSnapshot.State := dsDownloading;
  finally
    FLock.Leave;
  end;
end;

procedure TDownloadOperation.Run;
var
  LDM: TdmDownload;
  LStream: TDownloadFileStream;
  LPart, LBackup: string;
  LID: TGUID;
  LReserved: Boolean;
  LFinalState: TDownloadState;
  LError: string;
begin
  // An operation is single-use. Reject concurrent or repeated execution before
  // it can mutate the snapshot or acquire another destination reservation.
  FLock.Enter;
  try
    if FStarted then
      raise EInvalidOperation.Create('Download operation can only run once');
    FStarted := True;
  finally
    FLock.Leave;
  end;
  LReserved := False;
  LPart := '';
  LBackup := '';
  LFinalState := dsFailed;
  LError := '';
  try
    try
      CheckCancelled;
      if (FRequest.Destination = '') or
        not TDirectory.Exists(TPath.GetDirectoryName(FRequest.Destination)) then
        raise Exception.Create('Select an existing destination directory');
      TargetLock.Enter;
      try
        // This process-wide reservation prevents competing workers from publishing
        // to the same destination; other processes are outside this registry.
        if ActiveTargets.IndexOf(FRequest.Destination) >= 0 then
          raise Exception.Create('Another download is using this destination');
        ActiveTargets.Add(FRequest.Destination);
        LReserved := True;
      finally
        TargetLock.Leave;
      end;
      if TFile.Exists(FRequest.Destination) and not FRequest.AllowOverwrite then
        raise Exception.Create('Destination exists; overwrite was not approved');
      if CreateGUID(LID) <> 0 then
        raise Exception.Create('Unable to allocate a temporary download name');
      // Keep the temporary file beside the destination so publishing does not
      // require a cross-volume copy. Existing output survives transfer failure.
      LPart := FRequest.Destination + '.' + GUIDToString(LID) + '.part';
      SetState(dsConnecting);
      LStream := TDownloadFileStream.Create(LPart, Self);
      try
        // README: ownership and transfer lifecycle. Although its components are
        // designed in the IDE, this instance is streamed/used/freed on this thread.
        // No global dmDownload is shared between simultaneous transfers.
        LDM := TdmDownload.Create(nil);
        try
          LDM.Transfer(FRequest, LStream, Self);
        finally
          LDM.Free;
        end;
        SetTotal(LStream.Size);
      finally
        LStream.Free;
      end;
      CheckCancelled;
      if TFile.Exists(FRequest.Destination) then
      begin
        if not FRequest.AllowOverwrite then
          raise Exception.Create('Destination appeared during the download');
        // Replacement preserves the old output in a unique backup. Remove that
        // backup only on success; on failure retain it and report its location.
        LBackup := LPart + '.previous';
        TFile.Replace(LPart, FRequest.Destination, LBackup);
      end
      else
        TFile.Move(LPart, FRequest.Destination);
      LPart := '';
      LFinalState := dsCompleted;
    except
      on E: Exception do
      begin
        if IsCancelled then
          LFinalState := dsCancelled
        else
          LFinalState := dsFailed;
        LError := E.ClassName + ': ' + E.Message;
      end;
    end;
  finally
    // IOUtils raises on deletion failure. Keep cleanup failures as diagnostics
    // so reservation release and final snapshot publication still happen.
    if LPart <> '' then
      try
        TFile.Delete(LPart);
      except
        on E: Exception do
          LError := LError + ' Partial file could not be removed: ' +
            LPart + ' (' + E.Message + ')';
      end;
    if LBackup <> '' then
      if LFinalState = dsCompleted then
      begin
        try
          TFile.Delete(LBackup);
        except
          on E: Exception do
            LError := LError + ' Previous-file backup could not be removed: ' +
              LBackup + ' (' + E.Message + ')';
        end;
      end
      else if TFile.Exists(LBackup) then
        LError := LError + ' Previous-file backup retained: ' + LBackup;
    if LReserved then
    begin
      TargetLock.Enter;
      try
        ActiveTargets.Delete(ActiveTargets.IndexOf(FRequest.Destination));
      finally
        TargetLock.Leave;
      end;
    end;
    SetState(LFinalState, LError);
  end;
end;

class function TDownloadManager.CreateDownload(
  const ARequest: TDownloadRequest): TDownloadOperation;
begin
  Result := TDownloadOperation.Create(ARequest);
end;

constructor TDownloadWorker.Create(const ARequest: TDownloadRequest);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOperation := TDownloadManager.CreateDownload(ARequest);
end;

destructor TDownloadWorker.Destroy;
begin
  Cancel;
  // Join before freeing the operation: Execute can still be using its lock.
  inherited Destroy;
  FOperation.Free;
end;

procedure TDownloadWorker.Execute;
begin
  // A failed constructor can leave a suspended thread without an operation.
  if Assigned(FOperation) then
    FOperation.Run;
end;

procedure TDownloadWorker.Cancel;
begin
  Terminate;
  if Assigned(FOperation) then
    FOperation.Cancel;
end;

function TDownloadWorker.ReadSnapshot: TDownloadSnapshot;
begin
  Result := FOperation.ReadSnapshot;
end;

destructor TDownloadManager.TSession.Destroy;
begin
  // Session owns the worker, including exceptional startup/destruction paths.
  Worker.Free;
  inherited;
end;

constructor TDownloadManager.Create;
begin
  inherited Create;
  FSessions := TObjectList<TSession>.Create(True);
end;

destructor TDownloadManager.Destroy;
begin
  BeginShutdown;
  FSessions.Free;
  inherited;
end;

function TDownloadManager.StartDownload(const ARequest: TDownloadRequest): Int64;
var
  LSession: TSession;
begin
  if FShuttingDown then
    raise EInvalidOperation.Create('Download manager is shutting down');
  if FNextID = High(Int64) then
    raise EInvalidOperation.Create('Download session IDs exhausted');
  LSession := TSession.Create;
  try
    Inc(FNextID);
    LSession.ID := FNextID;
    LSession.URL := ARequest.URL;
    LSession.Worker := TDownloadWorker.Create(ARequest);
    LSession.Snapshot := LSession.Worker.ReadSnapshot;
    // Own the suspended worker before starting it. IDs are never recycled,
    // including failed starts, so delayed UI commands cannot target a new row.
    FSessions.Add(LSession);
  except
    LSession.Free;
    raise;
  end;
  try
    LSession.Worker.Start;
    Result := LSession.ID;
  except
    FSessions.Remove(LSession);
    raise;
  end;
end;

procedure TDownloadManager.Poll;
var
  LSession: TSession;
begin
  for LSession in FSessions do
    if Assigned(LSession.Worker) then
    begin
      LSession.Snapshot := LSession.Worker.ReadSnapshot;
      // A terminal snapshot precedes thread exit. State alone cannot prove
      // that joining/freeing during a UI poll will avoid a network wait.
      if LSession.Worker.Finished then
      begin
        LSession.Worker.WaitFor;
        LSession.Snapshot := LSession.Worker.ReadSnapshot;
        if Assigned(LSession.Worker.FatalException) then
        begin
          LSession.Snapshot.State := dsFailed;
          if LSession.Worker.FatalException is Exception then
            LSession.Snapshot.ErrorText :=
              Exception(LSession.Worker.FatalException).ClassName + ': ' +
              Exception(LSession.Worker.FatalException).Message
          else
            LSession.Snapshot.ErrorText := 'Unhandled worker exception';
        end;
        FreeAndNil(LSession.Worker);
      end;
    end;
end;

function TDownloadManager.ReadSessions: TArray<TDownloadSessionSnapshot>;
var
  I: Integer;
begin
  Poll;
  SetLength(Result, FSessions.Count);
  for I := 0 to FSessions.Count - 1 do
  begin
    Result[I].ID := FSessions[I].ID;
    Result[I].URL := FSessions[I].URL;
    Result[I].Progress := FSessions[I].Snapshot;
    Result[I].WorkerFinished := not Assigned(FSessions[I].Worker);
  end;
end;

function TDownloadManager.GetActiveCount: Integer;
var
  LSession: TSession;
begin
  Result := 0;
  if Assigned(FSessions) then
    for LSession in FSessions do
      if Assigned(LSession.Worker) then
        Inc(Result);
end;

function TDownloadManager.Cancel(AID: Int64): Boolean;
var
  LSession: TSession;
begin
  Result := False;
  for LSession in FSessions do
    if LSession.ID = AID then
    begin
      Result := Assigned(LSession.Worker);
      if Result then
        LSession.Worker.Cancel;
      Exit;
    end;
end;

function TDownloadManager.RemoveFinished(AID: Int64): Boolean;
var
  I: Integer;
begin
  Poll;
  Result := False;
  for I := 0 to FSessions.Count - 1 do
    if FSessions[I].ID = AID then
    begin
      Result := not Assigned(FSessions[I].Worker);
      if Result then
        FSessions.Delete(I);
      Exit;
    end;
end;

procedure TDownloadManager.ClearFinished;
var
  I: Integer;
begin
  Poll;
  for I := FSessions.Count - 1 downto 0 do
    if not Assigned(FSessions[I].Worker) then
      FSessions.Delete(I);
end;

procedure TDownloadManager.CancelAll;
var
  LSession: TSession;
begin
  if Assigned(FSessions) then
    for LSession in FSessions do
      if Assigned(LSession.Worker) then
        LSession.Worker.Cancel;
end;

procedure TDownloadManager.BeginShutdown;
begin
  FShuttingDown := True;
  CancelAll;
end;

initialization
  TargetLock := TCriticalSection.Create;
  ActiveTargets := TStringList.Create;
  {$IFNDEF MSWINDOWS}
  ActiveTargets.CaseSensitive := True;
  {$ENDIF}

finalization
  // The application must join all workers before unit finalization.
  ActiveTargets.Free;
  TargetLock.Free;

end.
