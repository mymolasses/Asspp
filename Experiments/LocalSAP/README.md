# Local SAP feasibility experiment

The 4.2.2.2 release uses the remote authentication settings. This branch probes
a local alternative, without changing the released login implementation.

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
