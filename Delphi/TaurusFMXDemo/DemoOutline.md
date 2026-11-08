# TaurusTLS 1.1 FireMonkey demo — presentation outline

## Purpose and central story

The demo shows how **OpenSSL library lifetime, TLS connections, certificate trust and background transfers** work together.

It uses a shared TaurusTLS loader with Indy HTTP and FTP clients. Two views carry the presentation:

- **OpenSSL Config:** configure and observe the shared OpenSSL runtime.
- **Downloads:** use that runtime through independent transfers, with protocol logs and certificate details.

TaurusTLS **1.1** is the demonstrated library release, not the OpenSSL version.

## Main capabilities

| Area | Demonstrated behavior |
| --- | --- |
| Loader | Design-time platform settings, runtime configuration, explicit initialization and reset after failure |
| Protocols | HTTP, HTTPS, FTP and explicit/implicit FTPS |
| Trust | Peer and hostname verification, custom PEM CA bundle, optional Windows certificate-store loading |
| Diagnostics | HTTP response headers and redirects, FTP control-channel log, server certificate-chain details |
| Transfers | Concurrent workers, progress, cooperative cancellation and retained results |
| Files | Streaming to temporary files, publishing on success and preserving existing destinations on transfer failure |
| Presentation UI | Expandable details, green/red results, Clear per session and Clear finished |
| Deployment | Platform OpenSSL configurations, CA bundles and static archive search-path variables |

## Suggested demonstration sequence

### 1. Make initialization visible

Start on **OpenSSL Config** with `LoadOnStart=False`.

Show the saved platform configuration alongside the current shared loader state. Explain the configurable library directory, version suffixes and OpenSSL configuration file.

Initialize OpenSSL and show the resulting version and state. On dynamic targets the action is **Load/Unload**; on static targets it is **Initialize/Uninitialize**.

**Message:** one shared runtime supplies the application's TLS consumers.

### 2. Perform a secure download

Switch to **Downloads**, enter an HTTPS URL, choose trust options and select a destination through Save As.

Expand the completed session to show:

- Response status and headers.
- Redirect history, where applicable.
- Server certificate-chain details.

HTTP/HTTPS URLs can identify a root, directory or query endpoint without containing a filename. The local destination is selected independently.

**Message:** the demo makes both the transfer result and the TLS evidence visible.

### 3. Show concurrency and cancellation

Start multiple downloads. Observe independent progress and cancel one transfer.

Explain that the UI polls copied snapshots while each transfer runs on its own worker. Once cleanup finishes, **Cancel** becomes **Clear**. Clearing a row removes its diagnostics, not the downloaded file.

**Message:** responsive presentation and explicit ownership are part of a reliable TLS application.

### 4. Compare FTP and FTPS

Show the control-channel port and select explicit or implicit FTPS.

| Mode | Default control port | TLS start |
| --- | --- | --- |
| FTP | 21 | No TLS |
| Explicit FTPS | 21 | AUTH TLS upgrade |
| Implicit FTPS | 990 | Immediately upon connection |

An explicit URL port overrides the default. FTPS also protects the data channel.

Expand the FTP log to show the command/response sequence. Password/account command arguments are masked.

**Message:** protocol negotiation can be inspected rather than inferred from a success label.

### 5. Demonstrate trust configuration

Use a prepared endpoint to compare a trust failure with a successful connection after supplying the appropriate CA bundle or Windows-store option.

The demo preserves certificate verification failures; it does not accept certificates merely to make a transfer succeed.

Explain the distinction between verification details and the chain actually supplied by the server. The server need not send a root certificate.

**Message:** trust configuration is an explicit part of establishing TLS.

## Optional lifecycle experiments

### Load OpenSSL on demand

This is an opt-in setup change before running: connect `TdmDownload.OnCreate` to the supplied `DataModuleCreate` handler.

That handler attaches the clients' `OnBeforeBind` events. In the tested Indy/TaurusTLS setup, the event runs before the TLS handler initializes, allowing the shared OpenSSL runtime to load on demand.

Restore the unassigned OnCreate event for the ordinary explicit-loading demonstration.

**Message:** the same loader supports explicit initialization and application-controlled initialization on demand.

### Intentionally unload during an active transfer

While downloads are active, the lifecycle button has a cover. Open the cover, then deliberately choose Unload/Uninitialize.

Explain before performing this experiment:

- The cover makes the action intentional.
- It does not make active native objects safe after unloading.
- An access violation can illustrate the lifetime violation.
- Normal operation keeps OpenSSL initialized until secure consumers and their cleanup have finished.

Treat this as a separate, potentially disruptive demonstration near the end, with a restart plan.

**Message:** library lifetime must encompass the lifetime of its consumers.

## Architecture slide

```text
Main form
  ├─ Shared loader data module
  └─ Download manager
       ├─ Worker → operation → data module → Indy client / TLS handler
       ├─ Worker → operation → data module → Indy client / TLS handler
       └─ Retained session snapshots → UI frames
```

Each transfer creates, uses and frees its own networking data module on its executing thread. The UI reads snapshots rather than live sockets or certificate pointers.

Normal application close requests cancellation and continues polling until worker cleanup completes.

## Cross-platform and build message

Windows/Linux use the existing dynamic-loading setup. Delphi macOS, Android and iOS targets select static OpenSSL archive linking.

The project provides target-specific `OSSL_LIB_*` search-path variables. `OSSL_LIB_MACOS` supplies universal macOS archives for Intel and ARM64. Static linking still requires runtime initialization, configuration files and trusted CA assets.

On macOS, provide an exported PEM trust bundle; OpenSSL does not directly use the system/user keychains.

Describe these as supported project configuration approaches. Do not imply every native target has completed build and runtime validation.

## Presentation preparation

- Use known, stable endpoints and sufficiently large files for progress/cancellation.
- Prepare a redirect example and a controlled trust example.
- Keep optional autoload and unload experiments distinct from the normal workflow.
- Have a restart ready for the deliberate unload experiment.
- Let the presenter perform application interactions and debugging.
- Keep implementation details on the architecture slide; lead the live demo with observable behavior.
