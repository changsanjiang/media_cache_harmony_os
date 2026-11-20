## Why

`server/` 中 `MCHttpResponse` 混合路由、业务 Fetcher 装配、HTTP 线格式与 chunked；`MCHttpConnectionHandler` 内嵌 mega-class 且硬编码 400/500。违反 SRP，不利单测与扩展路由。

## What Changes

- 新增 **`MCHttpWireEncoder`**：响应头、简单错误响应、chunked 编码。
- 新增 **`MCHttpRequestRouter`**：`requestTarget` → `IMCDataFetcher`（含 based_proxy 转换）。
- **`MCHttpResponse`** 退化为 Fetcher 适配器 + 委托 WireEncoder。
- **`MCHttpConnectionResponseHandler`** 独立文件；错误响应走 WireEncoder。
- Non-goals：HTTP pipeline 队列、Keep-Alive 策略、`parseRequest` 策略外移。

## Capabilities

### New Capabilities

- `mediacache-http-server-srp`: server 层 Wire/Router 拆分与职责边界。

### Modified Capabilities

（无）

## Impact

- `server/MCHttpResponse.ets`, `MCHttpConnectionHandler.ets`, 新增 `MCHttpWireEncoder.ets`, `MCHttpRequestRouter.ets`, `MCHttpConnectionResponseHandler.ets`
- `docs/ARCHITECTURE.md`