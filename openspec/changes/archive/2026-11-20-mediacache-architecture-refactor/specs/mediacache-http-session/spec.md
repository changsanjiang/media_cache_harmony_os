## ADDED Requirements

### Requirement: HTTP playback uses a single session fetcher per request

For asset-backed proxy routes, the library SHALL use one `IMCDataFetcher` implementation per TCP HTTP request that wraps media byte streaming (prepare, read, seek, abort).

#### Scenario: Session acquires asset for request lifetime

- **WHEN** a session fetcher is created for an asset-backed request
- **THEN** the library SHALL increment the asset readwrite reference count until the fetcher completes or aborts

#### Scenario: Session releases asset on completion

- **WHEN** the session fetcher reaches data end or aborts
- **THEN** the library SHALL decrement the asset readwrite reference count exactly once for that acquisition

### Requirement: RequestScope guarantees paired release

The library SHALL provide a request scope helper that pairs asset acquire and release in a finally-safe pattern for prefetch and export entry points.

#### Scenario: Prefetch releases asset after completion

- **WHEN** prefetch completes successfully or throws
- **THEN** the asset reference acquired for prefetch SHALL be released