# Local SAP feasibility experiment

The 4.2.x releases use the remote authentication settings. This 4.3 branch probes
a local alternative, without changing the released login implementation.

Shared fixes from 4.2.2.3 are merged here: storefront suffix parsing, token
rotation with a verification-code field, all-account download selection, and
version display from build settings. Version 4.3 identifies development of the
local implementation; it does not mean local SAP authentication is complete.

ipatool currently dynamically loads a desktop Unicorn library and executes an
x86-64 Apple guest. An iOS static Go archive alone does not replace that loader
or remove the default engine's JIT requirements.

The workflow pins Naville/unicorn feature/tci at
53471ef9cf480fab094bf13db3e5d2f9e2c30dc5, enables UNICORN_INTERPRETER,
runs an x86-64 instruction smoke test on macOS, and cross-compiles an arm64
iOS 16 static XCFramework. The fork's translate-all.c uses RW rather than RWX
code buffers in interpreter mode. Source: https://github.com/Naville/unicorn/tree/53471ef9cf480fab094bf13db3e5d2f9e2c30dc5

The Local SAP iOS App workflow now builds the static cgo adapter and exported
signing bridge, tests the machine and real Apple SAP handshake with dummy data,
cross-compiles both libraries, and links them into the iOS application.
AuthenticationService on this branch calls LocalSAPAuthenticator, never the
remote service. First use downloads hash-validated SAP assets directly from
Apple into the app sandbox's cache. No user credentials are used by CI.

Build locally on macOS with Go 1.25+ and Xcode:

```sh
bash Experiments/LocalSAP/build.sh /absolute/path/to/sap-libs
```

Set LOCAL_SAP_LIBRARY_DIR to that directory in Xcode build settings, or export
it when invoking the CI build script. This branch currently builds iOS arm64
only. A successful CI build still requires physical-device login/2FA/download
verification before treating the local implementation as production-ready.
