# TaurusTLS 1.1 FireMonkey Demo

A Delphi FireMonkey demonstration of the shared TaurusTLS OpenSSL loader and its use with Indy HTTP and FTP clients. The application makes the relationship between **library lifetime**, **TLS connections**, **certificate trust** and **background transfers** visible.

The two tabs tell one story: configure and initialize OpenSSL in **OpenSSL Config**, then use that shared runtime for independent downloads in **Downloads**. Protocol logs and certificate details explain what happened. Separate lifecycle experiments demonstrate loading on demand and intentionally unloading while a consumer is active.

TaurusTLS **1.1** is the library release demonstrated here; it is not an OpenSSL version number.

## Build and design-time setup

- Open `TaurusFMXDemo.dproj` in RAD Studio with Delphi/FireMonkey, Indy and the TaurusTLS components installed. The current development environment is RAD Studio 13; Win64/Debug is the recent compilation target.
- Define the IDE/environment path macro `TAURUSTLS_DEV` to the TaurusTLS source directory. The project includes `$(TAURUSTLS_DEV)` in its Delphi unit search path.
- On dynamically linked targets, supply OpenSSL libraries matching the executable's architecture and the TaurusTLS build configuration. Configure their search directory and any version suffixes in the Loader view before loading.
- For macOS, Android and iOS, configure the static OpenSSL archive paths described below. Supply the SDKs and deployment settings for the selected target.
- Forms, frames, data modules, event bindings and explanatory hints are defined in the `.fmx`/`.dfm` resources. Save edited IDE buffers before rebuilding or preparing presentation copies.

Other target configurations and conditional FPC code are present, but this project is an FMX application. Their presence does not establish tested mobile, macOS, Linux or Lazarus support.

## Building with statically linked OpenSSL

TaurusTLS automatically selects archive linking for Delphi macOS, Android and
iOS targets. The project supplies the archive search directories through
`DCC_UnitSearchPath` (Delphi Compiler search-path settings). These macros are
build-time paths on the development machine.

Define the following variables in RAD Studio's **Tools > Options > Environment
Options > Environment Variables**, or in the environment used by command-line
MSBuild. Set each value to a directory containing the corresponding OpenSSL
archives, rather than to an individual archive filename.

| Project target | Search-path variable(s), in project order | Required archive target |
| --- | --- | --- |
| Android | `OSSL_LIB_ANDROID32` | Android ARM 32-bit |
| Android64 | `OSSL_LIB_ANDROID64` | Android ARM 64-bit |
| iOSDevice64 | `OSSL_LIB_IOS64` | iOS ARM64 device |
| iOSSimARM64 | `OSSL_LIB_IOSARMSIM64` | iOS ARM64 simulator |
| OSX64 | `OSSL_LIB_MACOS`; `OSSL_LIB_MACOS64` | macOS Intel x86_64 |
| OSXARM64 | `OSSL_LIB_MACOS` | macOS ARM64 |

`OSSL_LIB_MACOS` is the shared directory for **universal macOS archives** with
both x86_64 and ARM64 slices. The exact macro spelling is `MACOS`. The additional
`OSSL_LIB_MACOS64` directory is searched after it for the Intel target; it can
hold Intel-specific archives when those are used instead. Keep earlier search
directories free of incompatible archives with the same names.

For example, `OSSL_LIB_ANDROID64=C:\OpenSSL\Android\arm64-v8a\lib` supplies
`libcrypto.a` and `libssl.a` for Android64. Use libraries built for the selected
platform, architecture and compatible SDK/toolchain. An ARM64 iOS device archive
cannot substitute for an ARM64 simulator archive, and macOS universal archives
do not substitute for iOS archives.

1. Obtain or build compatible static OpenSSL archives, including
   `libcrypto.a` and `libssl.a`, for each intended target. If an application
   includes `TaurusTLS_ProviderLegacy`, its static build also needs
   `liblegacy.a`.
2. Define the required variable(s), then select the corresponding platform and
   configuration in the IDE. Confirm the macros resolve in the compiler search
   path. For command-line builds, set the variables before starting MSBuild.
3. **Build** the project so the TaurusTLS units and application use the same
   target and linking configuration. No additional static-link conditional
   symbol is needed for these Delphi targets.
4. Deploy the platform configuration and CA bundles as described below, then
   initialize OpenSSL in the application before using TLS.

The linker incorporates the referenced archive code into the application; these
archives are not runtime files to deploy. Configuration files and trusted CA
certificates remain runtime assets. In particular, macOS still needs an exported
PEM trust bundle because OpenSSL does not directly use the system/user keychains.

The Loader's runtime library directory and suffix settings do not locate static
archives. **Initialize/Uninitialize** still controls the shared OpenSSL runtime;
uninitializing does not remove linked code from the executable.

Windows and Linux retain their existing dynamic-loading setup. The current
Win32 property group also contains macOS archive search paths; their presence
does not select static linking on Windows. These instructions describe the
project settings, not completed build/runtime validation on every listed target.

## Configuration files and deployment

Platform samples live in [conf](conf/README.md): openssl-win.cnf,
openssl-osx.cnf, openssl-linux.cnf, openssl-android.cnf and openssl-ios.cnf.
The generic openssl.cnf is an additional example. The samples set a TLS 1.2
minimum baseline and leave optional VerifyCAFile loading commented until the
corresponding public CA bundle is supplied.

The Loader's platform items select the sample automatically. Windows uses
`..\\..\\conf\\openssl-win.cnf` with the normal Platform/Config output layout;
other platforms use `conf/openssl-<platform>.cnf`, without a leading slash.

Startup calls `InitializeDemoPaths` before creating data modules. This deliberately
sets the process working directory once: executable directory on Windows/Linux,
bundle Contents/Resources on macOS, and Documents/internal extracted storage on
mobile. Both configuration filenames and paths inside OpenSSL configs use that
base. Relative paths entered in the UI use it too. No transfer changes the
working directory.

Distribute both `TaurusFMXDemo.dproj` (IDE deployment metadata) and
`TaurusFMXDemo.deployproj` (imported MSBuild deployment items), together with
the conf files. Entries cover Debug and Release. CA bundle copies are conditional
on the user-supplied files existing. See [conf/README.md](conf/README.md) for target
destinations, Windows distribution layout and macOS root-certificate export.
The supplied .pem.example is documentation, not a certificate bundle.

macOS requires a PEM trust bundle for this demo's OpenSSL setup; it does not
consult Keychain directly. Export the selected trusted roots on the Mac, deploy
macos-roots.pem, then enable VerifyCAFile in openssl-osx.cnf. The per-download
Root CA picker remains available independently. Native deployment still needs
validation on each target.

## Units and responsibilities

| Unit | Main types / resource | Responsibility |
| --- | --- | --- |
| [TaurusFMXDemo.dpr](TaurusFMXDemo.dpr) | Application entry point | Creates `dmConnect` before the main form. Does not auto-create a download module. |
| [TaurusFMXDemo.dmConnect.pas](TaurusFMXDemo.dmConnect.pas) | `TdmConnect`, `TLoaderSnapshot`; `.dfm` | Owns the design-time Loader, reads shared runtime state, applies pending settings, runs explicit load/unload, validates URLs and suggests local filenames. |
| [TaurusFMXDemo.frmLoader.pas](TaurusFMXDemo.frmLoader.pas) | `TfrmLoader`; `.fmx` | Presents configured/runtime settings, browse actions, lifecycle results and the deliberate-unload cover. |
| [TaurusFMXDemo.dmDownload.pas](TaurusFMXDemo.dmDownload.pas) | `TDownloadRequest`, `TDownloadSnapshot`, `TDownloadOperation`, `TDownloadWorker`, `TDownloadManager`, `TdmDownload`; `.dfm` | Contains protocol routing, diagnostics, file publication, cancellation, worker ownership and retained session results. No FMX controls or GUI callbacks. |
| [TaurusFMXDemo.fmxMain.pas](TaurusFMXDemo.fmxMain.pas) | `TfmxMain`; `.fmx` | Owns the manager, address/trust controls, Save As, session list, polling and coordinated application close. |
| [TaurusFMXDemo.frmDownloadSession.pas](TaurusFMXDemo.frmDownloadSession.pas) | `TfrmDownloadSession`; `.fmx` | Renders one copied snapshot: progress, result, Cancel/Clear, protocol log and PKI details. Owns no network objects. |

### Components

| Location | Component | Role |
| --- | --- | --- |
| `dmConnect` | `ttslLoader: TTaurusTLSLoader` | Configures the shared OpenSSL loader. `LoadOnStart=False` keeps initialization visible in the presentation. |
| Each `dmDownload` | `cliHTTP: TIdHTTP` | HTTP/HTTPS GET requests, response headers and redirects. |
| Each `dmDownload` | `cliFTP: TIdFTP` | Passive, binary FTP/FTPS transfers; explicit or implicit TLS and private FTPS data-channel protection. |
| Each `dmDownload` | `iohTLS: TTaurusTLSIOHandlerSocket` | Peer and hostname verification, custom CA trust, TLS connection and certificate events. |
| Each `dmDownload` | `logFTP: TTaurusTLSUnicodeLog` | UTF-8 diagnostic interception. It is wired at design time to the clients/shared handler in the supplied resource. HTTP header logging is also captured separately by `OnHeadersAvailable`. |
| Main form | `TActionList`, `TAction`, `TEdit`/`TEditButton`, `TSaveDialog`, `TOpenDialog` | Address validation, download command and destination/CA-file selection. Enter and Download use the same action. |
| Main form | FTPS `TRadioButton` pair, `TCheckBox` | TLS mode and Windows certificate-store selection for new requests. |
| Main form | `TListBox`, `TTimer` | Hosts session frames and polls the manager every 200 ms. |
| Frames | Labels/edits, buttons, progress bar, activity indicator, tabs, memos and popup menu | Copyable status, collapsible diagnostics and descriptive resource-defined hints. |

## Normal presentation workflow

1. Open **OpenSSL Config**. Compare the saved design-time configuration with the current shared loader values.
2. While inactive, choose the OpenSSL library search directory, configuration file and suffixes as appropriate. Use **Load** on dynamic targets or **Initialize** on static targets. A failed load offers **Unload/Uninitialize** to reset before retrying.
3. Open **Downloads**. Type, paste or drop a text URL into the address bar. A drop only fills and validates the address; it never starts a request.
4. Choose the FTPS mode when applicable. Optionally select a custom **PEM CA certificate bundle**. On Windows, choose whether to use the Windows certificate store.
5. Press **Download** or Enter. Choose a destination in **Save As**, approving replacement if necessary. Cancelling the picker creates no worker or output file.
6. Inspect the row while its background worker runs. Start additional downloads to demonstrate independent sessions. Received bytes are measured from file writes; the activity indicator is used when the total size is unknown.
7. Expand the chevron to inspect **Transfer log** and **PKI assets: server chain**. Successful status is green and failed status is red; state names remain visible.
8. Use **Cancel** to request cancellation. Once worker cleanup has finished, the same button becomes **Clear**. Clear removes the row and its diagnostics, not the destination file. **Clear finished** removes all finished rows.
9. For ordinary shutdown, let transfers finish or close the application. Closing requests cancellation and keeps polling until worker cleanup has completed.

### Protocol and destination selection

| URL / mode | Client | Default control port | TLS behavior |
| --- | --- | --- | --- |
| `http://` | `TIdHTTP` | 80 | Plain HTTP. |
| `https://` | `TIdHTTP` | 443 | TaurusTLS handler. |
| `ftp://` | `TIdFTP` | 21 | Plain FTP. |
| `ftps://`, Explicit TLS | `TIdFTP` | 21 | Connects, then requires an AUTH TLS upgrade. |
| `ftps://`, Implicit TLS | `TIdFTP` | 990 | TLS begins immediately. |

An explicit URI port takes precedence. The displayed FTP port is the **control** port; passive data ports are negotiated separately.

HTTP/HTTPS URLs may identify a host root, directory route or query endpoint without a filename. FTP/FTPS URLs must identify a remote file. Validation checks syntax, not reachability or resource existence. The local filename is chosen independently in Save As; the suggestion falls back to `download` when the URL has no basename.

## Ownership and transfer lifecycle

```text
Main form (UI thread)
  +-- Download manager
  |     +-- retained session ID, URL and copied result
  |     +-- worker thread -> download operation
  |                           +-- per-transfer data module and clients
  |                           +-- temporary output stream
  +-- list items -> session frames (presentation only)
```

A value-initialized `TDownloadRequest` copies the URL, destination, overwrite approval, FTPS mode and trust settings. Later UI changes do not reconfigure an existing request.

The manager creates a suspended worker, owns it before calling `Start`, and never recycles session IDs. The operation creates and frees its data module and stream on the executing thread. Only the selected client uses the shared handler **within that module**; different workers have different modules. Plain protocols detach the TLS handler.

The UI obtains snapshots under the operation's lock. It never reads live sockets or certificate pointers and does not receive worker `Queue`/`Synchronize` callbacks. The manager polls, joins only threads that have finished, and retains their final diagnostics. A terminal transfer state alone is not permission to destroy a still-running worker; `WorkerFinished` confirms cleanup.

Cancellation is cooperative. Indy work events and stream writes check the request; connect/read timeouts bound common waits. DNS or OS calls can delay cancellation. The shutdown path keeps the form and polling alive rather than pumping messages or freeing live workers.

### Publishing a downloaded file

Transfers stream to a unique adjacent GUID `.part` file, not to an in-memory copy of the payload. A process-wide reservation prevents concurrent demo sessions from publishing to the same destination.

Only a successful transfer publishes the destination. Replacement uses `TFile.Replace` with a unique previous-file backup. Transfer failure/cancellation preserves an existing destination; cleanup failures or a retained backup are included in the result. This is not a reservation against other processes or a resumable-download implementation.

### Trust and diagnostics

- Peer and hostname checks stay enabled. On Windows, the checkbox selects Windows ROOT/CA store loading; a custom PEM CA bundle can add trusted certificates. On other targets, the existing platform/default trust behavior remains.
- Each HTTP response contributes its status and headers, including redirect responses. Eight redirects may be followed; the ninth is rejected. Indy's strict counter comparison accounts for the resource's `RedirectMaximum=9`.
- The Unicode interceptor reports UTF-8 text, not arbitrary legacy code pages or decrypted TLS records by itself. FTP sent commands are buffered to complete lines before masking PASS/ACCT arguments. Masking does not remove credentials from a supplied URL or every possible diagnostic.
- Verification callbacks copy certificate details without accepting a failed preverification result. After negotiation, the server-sent chain is copied separately, leaf first. A verification path can include locally trusted certificates that the server did not send, and the server need not send a root CA.
- PKI views contain retained text descriptions, not live certificate objects or exported PEM files. Early handshake failure can leave only verification details or no certificates. Plain HTTP/FTP has no TLS certificate chain.
- The operation records original exception class/message for the session display. It does not replace TaurusTLS initialization failures with a demo precheck.

## Lifecycle experiments

### Load OpenSSL on demand

The normal resource leaves `TdmDownload.OnCreate` unassigned. For the presentation's optional autoload scenario, assign **OnCreate = DataModuleCreate** in the Object Inspector before running.

That handler wires both clients' `OnBeforeBind` to `OnBeforeBindHandler`, which attempts to load the shared runtime when needed. This demonstrates callback-driven loading using the supplied Indy/TaurusTLS setup. Restore the unassigned event for the explicit Loader-tab scenario. Registering this handler is opt-in; the demo does not silently load from a GUI update.

### Unload during an active transfer

While downloads are active, a cover replaces the lifecycle button. **Open cover to unload**, then deliberately press **Unload/Uninitialize**. **Close cover** restores the cover without changing the loader or cancelling a transfer.

The cover resets after use, when the active count changes, or when a new transfer starts. It guards action execution as well as mouse access. It makes the experiment intentional; it does **not** make native objects safe after their libraries are unloaded. An access violation during this experiment can demonstrate the lifetime problem. Normal operation keeps OpenSSL initialized until all secure consumers and their cleanup have finished.

## Reading and extending the code

Start with `TDownloadManager.StartDownload`, `TDownloadOperation.Run` and `TfmxMain.RefreshDownloads` for the ownership flow. Follow `Transfer`, `HTTPRedirect`, `TLSVerify` and `TLSNegotiated` for protocol/trust handling. `FormCloseQuery` and the unload-cover methods show the two deliberately different lifecycle paths.

`TDownloadManager.CreateDownload` also exposes the same operation for synchronous callers. Its `Run` blocks the calling thread; the main form's `ExecBlockingDownload` is a development helper, not the normal responsive GUI workflow.

The transfer layer is kept separate from FMX to support future reuse, but separate VCL/Lazarus frontends are not implemented here. Retries, resume, Content-Disposition filename selection and certificate export are not implemented.
