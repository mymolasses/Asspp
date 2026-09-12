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

A passing build is only the first gate. Remaining work includes static C bindings
instead of purego/dlopen, callback integration, sandbox-local SAP assets,
protocol/signing tests, then execution and login on a physical iOS 16 device.
No Apple credentials are used by this probe. This is not a working local signer.
