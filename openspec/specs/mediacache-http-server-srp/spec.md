# mediacache-http-server-srp Specification

## Purpose
Split the mediacache HTTP server layer by responsibility: centralized wire encoding (`MCHttpWireFormat`), isolated proxy routing (`MCHttpProxyRouter`), response streaming adapter (`MCHttpResponseAdapter`), and per-connection session (`MCHttpConnectionSession` / `MCHttpConnectionRegistry`).
## Requirements
### Requirement: HTTP wire format is centralized

The library SHALL encode outbound HTTP/1.1 response status lines and headers for playback responses through a single server wire encoder module.

#### Scenario: Error responses use shared formatter

- **WHEN** the connection layer must send 400 or 500 without an active response adapter
- **THEN** it SHALL use the same wire encoder as successful responses for consistent headers

### Requirement: Proxy path routing is isolated from response streaming

The library SHALL resolve an inbound `requestTarget` to an `IMCDataFetcher` in a dedicated router module, separate from response read/abort lifecycle.

#### Scenario: mc_proxy play request

- **WHEN** `requestTarget` starts with the standard proxy prefix after optional based-proxy conversion
- **THEN** the router SHALL return `MCMediaHttpSession` bound to the resolved asset

