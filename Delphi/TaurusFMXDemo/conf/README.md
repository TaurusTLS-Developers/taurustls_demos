# OpenSSL config and deployment assets

The active config is selected by dmConnect.ttslLoader.PlatformSettings. Each
openssl-<platform>.cnf is independent and loadable without a custom CA bundle.
openssl.cnf is a generic application-relative example. The samples set a TLS 1.2
minimum baseline; the IOHandler can subsequently apply its own context options.

## Path contract

InitializeDemoPaths runs once, before the Loader module and all workers.
It deliberately sets the process working directory, because both Loader.ConfigFile
and OpenSSL VerifyCAFile resolve relative paths from that directory. It never
changes directories while transfers run. User-entered relative library/CA paths
also follow this base.

| Target | Startup working directory | PlatformSettings.ConfigFile | Deployed config location |
| --- | --- | --- | --- |
| Win32/Win64/WinARM64EC | Executable directory | ..\..\conf\openssl-win.cnf | Project-root conf for normal Platform/Config output layout |
| Linux64 | Executable directory | conf/openssl-linux.cnf | conf beside executable |
| OSX64/OSXARM64 | App bundle Contents/Resources | conf/openssl-osx.cnf | Contents/Resources/conf |
| Android/Android64 | TPath.GetDocumentsPath | conf/openssl-android.cnf | assets/internal/conf, extracted by System.StartUpCopy |
| iOSDevice64/iOSSimARM64 | TPath.GetDocumentsPath | conf/openssl-ios.cnf | StartUp/Documents/conf |

There are no leading-slash platform config paths. RemoteDir in the Windows-side
project XML uses backslashes as required by the IDE's deployment format; the
deployed Unix layout still uses ordinary directory separators.

For Windows distribution, retain the two-level output layout (for example
distribution/Win64/Release/TaurusFMXDemo.exe and distribution/conf), or change BOTH
the Windows PlatformSettings path and demo_conf_dir inside openssl-win.cnf if you
package conf directly beside the executable. The relative library path already
configured in the demo is preserved.

## CA certificates

No private keys or fabricated CA certificates are supplied. The .pem.example
file is documentation, not a certificate and must never be loaded as a CA bundle.

1. Supply a PEM file containing the public CA certificates you intend to trust:
   custom-roots.pem (Windows/Linux), macos-roots.pem, android-roots.pem or
   ios-roots.pem. A PEM bundle can contain several BEGIN CERTIFICATE blocks.
2. Uncomment VerifyCAFile in the corresponding config. It references
   demo_conf_dir/demo_ca_bundle. Do not .include the PEM file: that directive
   parses configuration text.
3. Deploy the bundle with the config, unload/reset then load OpenSSL, and start a
   new secure transfer. A missing/invalid enabled bundle should be reported as an
   error rather than silently ignored.
4. The address bar's Root CA file remains an independent per-request option.
   Leave it blank when demonstrating CA trust from openssl.cnf alone.

macOS: the current handler has no native Keychain trust bridge. Export the
selected trusted root CA certificates using Keychain Access and combine their
PEM certificates into macos-roots.pem. To export the System Roots certificates
as a starting snapshot, run this ON THE MAC from the project's conf directory:

```sh
security find-certificate -a -p \
  /System/Library/Keychains/SystemRootCertificates.keychain > macos-roots.pem
```

Review the selected roots before use. Add only deliberately trusted certificates
from System/login keychains; do not export all user certificates indiscriminately.
An exported bundle does not reproduce Keychain trust overrides, revocation rules
or later changes. Do not export private keys. This Windows workspace cannot
export your Mac's roots; you must supply that file before enabling its config
line. Without a configured PEM/default OpenSSL trust bundle, a macOS TLS download
can fail verification even though a browser trusts the server.

Windows can retain its Windows ROOT/CA-store checkbox; Linux may use OpenSSL's
existing default CA paths. Loading a PEM bundle through OpenSSL configuration is
a separate demonstration from those platform defaults. VerifyCAFile remains
commented initially so merely selecting a sample never trusts an unspecified CA.

## Project and deployment files to distribute

Keep these in source control/distribution together:
- TaurusFMXDemo.dproj: IDE project, platform settings and Deployment Manager data.
- TaurusFMXDemo.deployproj: imported MSBuild deployment items and destinations.
- All conf/openssl-*.cnf files, this document and the public CA bundles you choose.

Config deployment entries cover Debug and Release. Bundle entries in deployproj
use Exists conditions so absent user-supplied bundles are not copied. Once a
bundle is supplied, it must also appear in the target's Deployment Manager view;
check the generated deployproj after using the IDE to regenerate deployment data.
The sample metadata is not a substitute for supplying OpenSSL binaries/SDKs or
validating deployment on a real target. Windows local builds read project/conf
directly; Deployment Manager's Windows operation is None, not an automatic
post-build copy. A .deployproj may be regenerated by the IDE, so review it before
committing changes. Never ship the .pem.example placeholder as a trust bundle.

Sources:
- https://docs.openssl.org/3.0/man5/config/
- https://docs.openssl.org/3.0/man3/SSL_CONF_cmd/
- https://support.apple.com/guide/keychain-access/import-and-export-keychain-items-kyca35961/mac
- https://docwiki.embarcadero.com/RADStudio/Florence/en/Creating_an_Android_App
