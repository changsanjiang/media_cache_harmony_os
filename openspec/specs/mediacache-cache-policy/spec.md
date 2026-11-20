# mediacache-cache-policy Specification

## Purpose
TBD - created by archiving change mediacache-architecture-refactor. Update Purpose after archive.
## Requirements
### Requirement: In-use assets are not evicted

The cache manager SHALL NOT delete on-disk cache or abort an asset that has a positive readwrite reference count on the in-memory asset instance.

#### Scenario: Skip eviction during playback

- **WHEN** periodic or size-based trim selects an assetId for eviction
- **AND** the in-memory asset has readwriteCount greater than zero
- **THEN** the cache manager SHALL skip evicting that assetId in this pass

#### Scenario: Pinned assets remain protected

- **WHEN** an asset is pinned
- **THEN** the cache manager SHALL NOT evict that assetId (existing behavior preserved)

### Requirement: Eviction consults policy before removeAssetBy

The cache manager SHALL filter candidate asset IDs through `canEvict(assetId)` before calling `removeAssetBy`.

#### Scenario: In-use asset retained on disk after trim

- **WHEN** trim runs while a client is actively reading the asset
- **THEN** the asset files SHALL remain and the active read SHALL continue

