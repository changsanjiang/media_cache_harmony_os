## 1. Domain & capability registry (P0)

- [x] 1.1 Add `MCAssetCapabilities` / `MCAssetCapabilityRegistry` under `defines/` or `asset/`
- [x] 1.2 Register FILE / HLS / DASH capabilities (export flags match current product)
- [x] 1.3 Refactor `MCAssetPrefetchManager` to use registry; wire `DashAssetPrefetcher`

## 2. Request scope (P1)

- [x] 2.1 Add `MCRequestScope` helper for paired retain/release
- [x] 2.2 Use scope in prefetch/export managers (replace manual retain/finally)

## 3. Cache policy (P1)

- [x] 3.1 Add `MCCachePolicy` / `MCAssetManager.isAssetInUse(assetId)`
- [x] 3.2 Filter `evictAssets` candidates with `canEvict`

## 4. HTTP session layer (P2)

- [x] 4.1 Add `MCMediaHttpSession` implementing `IMCDataFetcher` (delegate existing media fetcher logic)
- [x] 4.2 Switch `MCHttpResponse` asset routes to `MCMediaHttpSession`
- [x] 4.3 Remove deprecated `MCAssetDataFetcher` alias class

## 5. Docs & export manager (P3)

- [x] 5.1 Refactor `MCAssetExportManager` type switch to use capability registry + clear error for unsupported
- [x] 5.2 Update `docs/ARCHITECTURE.md` with invariants, session, policy sections

## 6. Verification (P4)

- [x] 6.1 Add unit test for `MCCachePolicy` / in-use skip (or extend NodeList test file pattern)
- [x] 6.2 Manual checklist note in change README for entry AVPlayer play + DASH prefetch call