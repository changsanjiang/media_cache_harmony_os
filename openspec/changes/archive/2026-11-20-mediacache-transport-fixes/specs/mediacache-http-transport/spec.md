## ADDED Requirements

### Requirement: HTTP request headers may arrive over multiple TCP segments

The server SHALL buffer incoming bytes per connection until a complete request header block (terminated by CRLFCRLF) is available before parsing.

#### Scenario: Partial header then completion

- **WHEN** the first TCP segment does not contain CRLFCRLF
- **THEN** the server SHALL wait for more data without closing the connection

#### Scenario: Complete header in one segment

- **WHEN** CRLFCRLF is present in the buffer
- **THEN** the server SHALL parse one request and retain any following bytes for the next request

### Requirement: HEAD responses omit message body

The server SHALL send response headers consistent with GET for the same resource when the request method is HEAD, and MUST NOT send a response body.

#### Scenario: HEAD on cached media

- **WHEN** the client sends HEAD for a valid proxy path
- **THEN** the server SHALL respond with the same status and length-related headers as GET and MUST NOT write a response body to the connection