/// <summary>Shared Loader control, startup paths and download-address helpers for the demo.</summary>
unit TaurusFMXDemo.dmConnect;

{$I TaurusTLSCompilerDefines.inc}
{$I TaurusTLSLinkDefines.inc}

interface

uses
  SysUtils, Classes, TaurusTLSLoader, System.Net.URLClient, System.NetEncoding,
  System.IOUtils;

type
  /// <summary>Copied shared-loader values for presentation without retaining native OpenSSL objects.</summary>
  /// <remarks>Metadata is passive. Public State alone does not describe every lifecycle transition; Busy tracks this controller's own operations.</remarks>
  TLoaderSnapshot = record
    /// <summary>Public shared-loader state; a failed state requires reset before retry.</summary>
    State: TTaurusTLSLoaderState;
    /// <summary>Whether this target loads shared libraries rather than linking OpenSSL statically.</summary>
    DynamicLinking: Boolean;
    /// <summary>True while this data module is executing its own Load or Unload operation.</summary>
    Busy: Boolean;
    /// <summary>Runtime OpenSSL version metadata; normally empty while inactive.</summary>
    Version: string;
    /// <summary>Configured dynamic-library search directory, not a resolved loaded-library filename.</summary>
    OpenSSLPath: string;
    /// <summary>Configured filename while inactive, or effective configuration filename while ready.</summary>
    ConfigFile: string;
    /// <summary>Dynamic-library suffix search list; empty on statically linked targets.</summary>
    SSLLibVersions: string;
    /// <summary>OpenSSL engine-directory metadata, which can be empty on unsupported versions.</summary>
    EnginesDirectory: string;
    /// <summary>Compiled OpenSSL module directory, not necessarily the configured provider location.</summary>
    ModulesDirectory: string;
  end;

  /// <summary>Owns the design-time Loader and exposes nonvisual helpers to the FMX presentation.</summary>
  /// <remarks>The DPR creates this module before the main form. Call lifecycle methods from the UI thread; the busy flag is a reentrancy guard, not a worker-thread lock.</remarks>
  TdmConnect = class(TDataModule)
    /// <summary>Design-time component supplying platform settings to the shared OpenSSL loader.</summary>
    ttslLoader: TTaurusTLSLoader;
  private
    FBusy: Boolean;
  public
    /// <summary>Checks the address syntax accepted by the demo without performing network I/O.</summary>
    /// <param name="AURL">HTTP, HTTPS, FTP or FTPS address; surrounding whitespace is trimmed.</param>
    /// <param name="AError">Empty on success; otherwise a user-facing validation reason.</param>
    /// <returns>True for an accepted address. HTTP endpoints need no basename; FTP requires a remote filename.</returns>
    /// <remarks>Uses TURI for syntax checks. Does not resolve DNS, authenticate or establish whether a resource exists.</remarks>
    function ValidateDownloadURL(const AURL: string; out AError: string): Boolean;
    /// <summary>Derives a safe local filename suggestion from the URL path.</summary>
    /// <param name="AURL">Address whose query and fragment are excluded from the suggestion.</param>
    /// <returns>A sanitized basename, or download when no usable basename is present.</returns>
    /// <remarks>Does not inspect Content-Disposition or validate the URL; Save As remains authoritative.</remarks>
    function SuggestDownloadFilename(const AURL: string): string;
    /// <summary>Copies current public state and metadata from the shared loader.</summary>
    /// <returns>A value snapshot with this controller's Busy flag and the target linking model.</returns>
    /// <remarks>Does not initialize OpenSSL or lease its lifetime. Individual property reads are not a transaction against external lifecycle changes.</remarks>
    function ReadLoader: TLoaderSnapshot;
    /// <summary>Replaces a caller-owned string list with the saved settings for the current platform.</summary>
    /// <param name="ADestination">Non-nil destination list; ownership remains with the caller.</param>
    /// <remarks>Shows raw configuration separately from runtime metadata and explicitly reports missing entries/default selection.</remarks>
    procedure DescribeDesignSettings(ADestination: TStrings);
    /// <summary>Applies pending inactive settings and requests shared OpenSSL initialization.</summary>
    /// <param name="ALibraryPath">Dynamic-library search directory; ignored for static linking.</param>
    /// <param name="AConfigFile">OpenSSL configuration filename, or empty for default initialization.</param>
    /// <param name="ALibraryVersions">Library suffix search list; ignored for static linking.</param>
    /// <returns>The result of the shared loader's Load call.</returns>
    /// <exception cref="Exception">A controller operation is already active, the loader is not inactive, or the underlying loader rejects a setting or initialization.</exception>
    /// <remarks>Restores Busy even on failure. Does not create download consumers or coordinate their lifetime.</remarks>
    function LoadOpenSSL(const ALibraryPath, AConfigFile,
      ALibraryVersions: string): Boolean;
    /// <summary>Requests shared OpenSSL unload/uninitialization, including failed-state reset.</summary>
    /// <exception cref="Exception">A controller operation is active or the underlying unload fails.</exception>
    /// <remarks>Does not cancel or join consumers. The caller must coordinate normal lifetimes; the demo separately permits deliberate active-transfer experiments.</remarks>
    procedure UnloadOpenSSL;
  end;

// Called once before constructing data modules; see conf/README.md.
/// <summary>Sets the process working directory once for the demo's relative configuration paths.</summary>
/// <remarks>Call before module creation and worker startup. Uses the executable directory on Windows/Linux, bundle Resources on macOS, and Documents/internal assets on mobile. See conf/README.md.</remarks>
/// <exception cref="Exception">The startup base cannot be resolved or selected.</exception>
procedure InitializeDemoPaths;

var
  dmConnect: TdmConnect;

implementation

{$IFNDEF FPC}
{%CLASSGROUP 'System.Classes.TPersistent'}
{$R *.dfm}
{$ELSE}
{$R *.lfm}
{$ENDIF}

procedure InitializeDemoPaths;
var
  LBase: string;
begin
  // Both Loader.ConfigFile and OpenSSL's VerifyCAFile use the process working
  // directory. Establish one stable base before components or workers exist.
  // Do not change directories per transfer: that would race other workers.
  {$IF DEFINED(ANDROID) OR DEFINED(IOS)}
  LBase := TPath.GetDocumentsPath; // FMX extracts assets/internal (StartUp) here.
  {$ELSE}
  LBase := ExtractFilePath(ParamStr(0));
  {$IFDEF MACOS}
  LBase := TPath.Combine(LBase, '../Resources');
  {$ENDIF}
  {$IFEND}
  LBase := TPath.GetFullPath(LBase);
  if not SetCurrentDir(LBase) then
    raise Exception.CreateFmt('Cannot select demo configuration base: %s', [LBase]);
end;

function TdmConnect.ValidateDownloadURL(const AURL: string;
  out AError: string): Boolean;
var
  LURI: TURI;
  LURL, LFilename: string;
  I: Integer;
begin
  Result := False;
  // README: protocol and destination selection. This is syntax validation only;
  // it must not resolve hosts or perform network I/O on the GUI thread.
  LURL := Trim(AURL);
  AError := 'Enter a download URL.';
  if LURL = '' then Exit;
  AError := 'Use http://, https://, ftp:// or ftps://.';
  if Pos('://', LURL) = 0 then Exit;
  try
    LURI := TURI.Create(LURL);
  except
    on E: Exception do
    begin
      AError := 'Invalid URL: check the scheme, host and port.';
      Exit;
    end;
  end;
  if not (SameText(LURI.Scheme, 'http') or SameText(LURI.Scheme, 'https') or
    SameText(LURI.Scheme, 'ftp') or SameText(LURI.Scheme, 'ftps')) then Exit;
  AError := 'Enter a valid host name or IP address.';
  if (LURI.Host = '') or (Pos('..', LURI.Host) > 0) then Exit;
  for I := 1 to Length(LURI.Host) do
    if (Ord(LURI.Host[I]) <= 32) or
      (Pos(LURI.Host[I], '/\@?#%') > 0) then Exit;
  AError := 'Encode spaces and use forward slashes in the URL.';
  for I := 1 to Length(LURL) do
    if (Ord(LURL[I]) <= 32) or (LURL[I] = '\') then Exit;
  AError := 'Use a port between 1 and 65535.';
  if (LURI.Port = 0) or (LURI.Port < -1) or (LURI.Port > 65535) then Exit;
  AError := 'Use valid percent escapes, such as %20.';
  I := 1;
  while I <= Length(LURL) do
  begin
    if LURL[I] = '%' then
    begin
      if I + 2 > Length(LURL) then Exit;
      if (Pos(UpCase(LURL[I + 1]), '0123456789ABCDEF') = 0) or
        (Pos(UpCase(LURL[I + 2]), '0123456789ABCDEF') = 0) then Exit;
      Inc(I, 2);
    end;
    Inc(I);
  end;
  // HTTP resources may be a host root, directory route or query endpoint.
  // Save As supplies the local filename independently of the URL path.
  if SameText(LURI.Scheme, 'http') or SameText(LURI.Scheme, 'https') then
  begin
    AError := '';
    Exit(True);
  end;
  AError := 'Include a file name in the FTP URL path.';
  LFilename := Copy(LURI.Path, LastDelimiter('/', LURI.Path) + 1, MaxInt);
  LFilename := TNetEncoding.URL.Decode(
    StringReplace(LFilename, '+', '%2B', [rfReplaceAll]));
  if (LFilename = '') or (LFilename = '.') or (LFilename = '..') then Exit;
  for I := 1 to Length(LFilename) do
    if (Ord(LFilename[I]) < 32) or (Pos(LFilename[I], '/\') > 0) then Exit;
  AError := '';
  Result := True;
end;

function TdmConnect.SuggestDownloadFilename(const AURL: string): string;
var
  LPath: string;
  I: Integer;
begin
  LPath := Trim(AURL);
  I := Pos('#', LPath);
  if I > 0 then
    Delete(LPath, I, Length(LPath));
  I := Pos('?', LPath);
  if I > 0 then
    Delete(LPath, I, Length(LPath));
  I := Pos('://', LPath);
  if I > 0 then
  begin
    Delete(LPath, 1, I + 2);
    I := Pos('/', LPath);
    if I = 0 then
      LPath := ''
    else
      Delete(LPath, 1, I);
  end;
  Result := Copy(LPath, LastDelimiter('/', LPath) + 1, MaxInt);
  for I := 1 to Length(Result) do
    if (Ord(Result[I]) < 32) or (Pos(Result[I], '<>:"/\|?*') > 0) then
      Result[I] := '_';
  while (Result <> '') and ((Result[Length(Result)] = '.') or
    (Result[Length(Result)] = ' ')) do
    Delete(Result, Length(Result), 1);
  if Result = '' then
    Result := 'download';
end;

function TdmConnect.ReadLoader: TLoaderSnapshot;
var
  LLoader: IOpenSSLLoader;
begin
  LLoader := GetOpenSSLLoader;
  Result.State := LLoader.State;
  Result.DynamicLinking := {$IFDEF OPENSSL_STATIC_LINK_MODEL}False{$ELSE}True{$ENDIF};
  Result.Busy := FBusy;
  Result.Version := LLoader.Version;
  Result.OpenSSLPath := LLoader.OpenSSLPath;
  Result.ConfigFile := LLoader.ConfigFile;
  Result.SSLLibVersions := LLoader.SSLLibVersions;
  Result.EnginesDirectory := LLoader.EnginesDirectory;
  Result.ModulesDirectory := LLoader.ModulesDirectory;
end;

procedure TdmConnect.DescribeDesignSettings(ADestination: TStrings);
const
  TargetNames: array[TTaurusTLSPlatform] of string =
    ('Android', 'iOS', 'macOS', 'Linux', 'Windows32', 'Windows64');
var
  LTarget: TTaurusTLSPlatform;
  LSettings: TTaurusTLSPlatformSetting;
begin
  LTarget := TTaurusTLSLoader.CurrentTarget;
  LSettings := ttslLoader.PlatformSettings.FindTarget(LTarget);
  ADestination.BeginUpdate;
  try
    ADestination.Clear;
    ADestination.Add('Platform: ' + TargetNames[LTarget]);
    ADestination.Add('LoadOnStart: ' + BoolToStr(ttslLoader.LoadOnStart, True));
    if LSettings = nil then
      ADestination.Add('No platform entry: defaults selected')
    else
    begin
      ADestination.Add('OpenSSLPath: ' + LSettings.OpenSSLPath);
      ADestination.Add('ConfigFile: ' + LSettings.ConfigFile);
      ADestination.Add('CustomSSLLibVersions: ' + LSettings.CustomSSLLibVersions);
    end;
    ADestination.Add('Blank configured fields select defaults.');
  finally
    ADestination.EndUpdate;
  end;
end;

function TdmConnect.LoadOpenSSL(const ALibraryPath, AConfigFile,
  ALibraryVersions: string): Boolean;
var
  LLoader: IOpenSSLLoader;
begin
  if FBusy then
    raise Exception.Create('A loader operation is already in progress');
  FBusy := True;
  try
    LLoader := GetOpenSSLLoader;
    if LLoader.State <> lsNotLoaded then
      raise Exception.Create('Unload or uninitialize OpenSSL before changing settings');
    {$IFNDEF OPENSSL_STATIC_LINK_MODEL}
    LLoader.OpenSSLPath := ALibraryPath;
    LLoader.SSLLibVersions := ALibraryVersions;
    {$ENDIF}
    LLoader.ConfigFile := AConfigFile;
    Result := LLoader.Load;
  finally
    FBusy := False;
  end;
end;

procedure TdmConnect.UnloadOpenSSL;
begin
  if FBusy then
    raise Exception.Create('A loader operation is already in progress');
  FBusy := True;
  try
    GetOpenSSLLoader.Unload;
  finally
    FBusy := False;
  end;
end;

end.
