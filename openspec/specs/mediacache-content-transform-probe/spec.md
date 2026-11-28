# mediacache-content-transform-probe Specification

## Purpose

Lightweight origin probe and placeholder metadata for media that require whole-body content transformation (HLS/DASH playlists).

## Requirements

### Requirement: Transform media probe SHALL use Range bytes=0-1

When an `MCMedia` instance has a content transformer, `probe` SHALL issue a GET with `Range: bytes=0-1` to the origin URL and SHALL NOT download or persist the full origin body during probe.

#### Scenario: Probe accepts 200 or 206

- **WHEN** the origin responds with status 200 or 206 to `bytes=0-1`
- **THEN** `probe` SHALL succeed and SHALL read `Content-Type` from response headers

### Requirement: Transform media probe SHALL persist placeholder metadata

When a content transformer is configured and the resource is not empty, `probe` SHALL set `totalLength` to `Number.MAX_SAFE_INTEGER`, `byteRangeAccessSupported` to `false`, and SHALL persist metadata to disk before the first full GET completes.

#### Scenario: Full body transform happens in loader

- **WHEN** a client performs GET on transformed playlist media after probe
- **THEN** the full download and content transformation SHALL occur in `MCMediaTransformContentLoader`, not in `probe`

### Requirement: Probe SHALL recognize empty origin resources

`probe` with `Range: bytes=0-1` SHALL treat HTTP 416, `Content-Length: 0`, or `Content-Range` total size 0 as an empty resource and SHALL set `totalLength` to 0 without requiring a full-body download.

#### Scenario: Empty playlist skips transform loader

- **WHEN** the origin responds with 416 or zero total size to `bytes=0-1` and the media has a content transformer
- **THEN** `probe` SHALL persist `totalLength: 0` and subsequent GET SHALL NOT spawn `MCMediaTransformContentLoader` for non-empty fetch

### Requirement: Placeholder metadata SHALL trigger content cleanup on prepare

When persisted metadata has `totalLength === Number.MAX_SAFE_INTEGER`, `MCMediaContentProvider.prepare` SHALL remove untrusted content files under that media directory before loading cached blocks.

#### Scenario: Interrupted download after placeholder probe

- **WHEN** the app restarts with placeholder metadata and partial content files on disk
- **THEN** `prepare` SHALL delete those content files so the next fetch uses a clean transform pipeline