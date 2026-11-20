## Why

本地代理 TCP 层假定「一次 `message` 事件 = 完整 HTTP 请求」，半包会导致 400 关连接；HEAD 被解析但仍走完整 `fetch` 并发送 body，不符合 HTTP 语义且浪费流量。

## What Changes

- 连接级**接收缓冲**，按 `\r\n\r\n` 拆出完整请求头后再解析；限制最大头部长度。
- **`IMCDataRequest.method`**（GET/HEAD）贯穿 `MCHttpResponse` → 会话/Media。
- **HEAD**：仅 `probe` + 响应头，无响应体；连接层不 `consumeData`。
- 请求体策略：拒绝带 `Content-Length` 的入站 body（GET/HEAD 无 body）。
- **Non-goals**：HTTP/2、pipeline 队列、多 Range 响应。

## Capabilities

### New Capabilities

- `mediacache-http-transport`: TCP 读缓冲、HEAD 语义、入站请求完整性。

### Modified Capabilities

（无）

## Impact

- `server/MCHttpConnectionHandler.ets`, `MCHttpRequest.ets`, `MCHttpResponse.ets`
- `defines/IMCDataRequest.ets`, `IMCDataFetcher` 消费方
- `media/MCMedia.ets`, `session/MCMediaHttpSession.ets`, `virtual/MCVirtualResourceDataFetcher.ets`