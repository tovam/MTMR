# Vendored WebSocket packages

MMTMR vendors the server-only sources from:

- `hummingbird-websocket` 2.7.0;
- `swift-websocket` 1.6.1 (`WSCore` only).

The upstream `swift-websocket` 1.6.1 `Span` optimization does not compile with
Swift 6.2 when the deployment target predates macOS 26. The vendored copy keeps
the functionally equivalent `ByteBuffer` implementation for fragmented text
messages. Each package retains its Apache 2.0 license and original source
headers.
