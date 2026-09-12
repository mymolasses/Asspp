# Apple protocol sync

This fork vendors its patched ApplePackage dependency under
`Vendor/ApplePackage`. No separate ApplePackage fork is required.

The dependency carries the Apple protocol fixes already validated in
`mymolasses/AssppWeb`:

- Resolve the current native authentication endpoint from Apple's bag.
- Preserve cookies by name, domain, and path so authentication state remains
  available when a request moves between Apple service subdomains.
- Keep `volumeStoreDownloadProduct` as the primary download endpoint.
- Use the bag-advertised `/up/updateProduct` endpoint when the primary service
  returns an empty successful response.
- Retain `/r/redownload` as the final fallback for failure type `5002` or when
  the newer endpoint is unavailable or also empty.

The endpoint URL read from the bag is accepted only when it is HTTPS and points
to `downloaddispatch.itunes.apple.com/up/updateProduct`, preventing account
cookies from being sent to an unexpected host.
