# mediacache-domain Specification

## Purpose
TBD - created by archiving change mediacache-architecture-refactor. Update Purpose after archive.
## Requirements
### Requirement: Asset aggregates one or more Media resources

The library SHALL model a playback resource as an `IMCAsset` identified by `assetId`, containing one or more `IMCMedia` instances (single file for FILE_BASED, multiple for HLS/DASH).

#### Scenario: FILE asset has one media

- **WHEN** the asset type is FILE_BASED
- **THEN** `getMediaByProxyPath` SHALL resolve to the sole root media for that asset

#### Scenario: HLS asset resolves media by proxy path

- **WHEN** the asset type is HLS and a proxy path identifies a segment or playlist mediaId
- **THEN** the asset SHALL lazily create or return the matching `IMCMedia` for that mediaId

### Requirement: Capability matrix is authoritative per asset type

The library SHALL expose a capability matrix for each `MCAssetType` declaring whether remote play, prefetch, export, and local-dir play are supported.

#### Scenario: DASH supports remote play and prefetch

- **WHEN** the asset type is DASH
- **THEN** the capability matrix SHALL mark remote play and prefetch as supported and export as unsupported until implemented

#### Scenario: FILE supports all primary operations

- **WHEN** the asset type is FILE_BASED
- **THEN** the capability matrix SHALL mark remote play, prefetch, export, and local-dir play as supported

### Requirement: Proxy path resolves asset before media

For routes under `/mc_proxy` and `/mc_based_proxy`, the server SHALL resolve `IMCAsset` via `MCAssetManager` before reading bytes from `IMCMedia`.

#### Scenario: Play request uses asset then media

- **WHEN** a valid `/mc_proxy` GET request is received
- **THEN** the server SHALL obtain the asset by proxy path, then the media by the same path, then stream via the HTTP session layer

