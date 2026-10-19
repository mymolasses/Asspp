# Local SAP for native iOS

The native app embeds the SAP modules from ipatool **v2.7.0**, pinned to
`4484b55d366e177ae6c89758c61588712c572fad`. Swift calls an exported C/Go
bridge for login action signatures and account/device-bound download kbsync.
No remote AssppWeb signing service is required.

The upstream desktop Unicorn loader is replaced with a static cgo adapter to
Naville/unicorn `53471ef9cf480fab094bf13db3e5d2f9e2c30dc5`, with
`UNICORN_INTERPRETER=ON`. Apple x86-64 code runs in the interpreter; no JIT is
introduced. Hash-validated Apple assets and StoreAgent are loaded from Apple
and cached inside the sandbox supplied by Swift.

Build with Xcode, Go 1.25+ and CMake 3.31:

```sh
bash Experiments/LocalSAP/build.sh /absolute/path/to/sap-libs
```

Set `LOCAL_SAP_LIBRARY_DIR` to the output directory when building the app.
The output contains `libasspp-sap.a`, `libasspp-sap.h`, and `libunicorn.a` for
iOS arm64. The compiler wrapper keeps target detection correct on Intel and
Apple silicon build hosts.

The script runs upstream machine, image and archive tests; sandbox-cache and
bridge-input tests; a real Apple SAP handshake with dummy input; and kbsync
generation with dummy identifiers. These tests do not use an Apple account.
Physical-device login, 2FA and downloads still require manual verification.

See [alignment details](../../Resources/Document/IPATOOL_2_7_ALIGNMENT.md).
