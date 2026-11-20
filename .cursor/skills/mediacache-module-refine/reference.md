# server 域改造参考（事实标准）

## 文件与职责（当前）

| 文件 | 类/符号 | 职责 |
|------|---------|------|
| `MCTcpSocketServer.ets` | `MCTcpSocketServer` | 127.0.0.1 listen，转发 connect |
| `MCHttpConnectionRegistry.ets` | `MCHttpConnectionRegistry` | clientId → Session 注册表 |
| `MCHttpConnectionSession.ets` | `MCHttpConnectionSession` | 缓冲→parse→ResponseAdapter→socket 泵 |
| `MCHttpReceiveBuffer.ets` | `MCHttpReceiveBuffer` | 半包/粘包头块 |
| `MCHttpRequest.ets` | `parseRequest` | 入站 GET/HEAD 解析 |
| `MCHttpProxyRouter.ets` | `MCHttpProxyRouter` | proxyPath → `IMCDataFetcher` |
| `MCHttpWireFormat.ets` | `MCHttpWireFormat` | 200/206/400/500 + chunked |
| `MCHttpResponseAdapter.ets` | `MCHttpResponseAdapter` | `IMCHttpResponse` ← Fetcher |
| `MCHttpLog.ets` | `MCHttpLog` | `summarizeRequest` |

## 重命名对照（历史）

| 旧 | 新 |
|----|-----|
| `MCHttpConnectionHandler` | `MCHttpConnectionRegistry` |
| `MCHttpConnectionResponseHandler` | `MCHttpConnectionSession` |
| `MCHttpResponse` | `MCHttpResponseAdapter` |
| `MCHttpRequestRouter` | `MCHttpProxyRouter` |
| `MCHttpWireEncoder` | `MCHttpWireFormat` |

## OpenSpec

- `mediacache-http-transport` — 半包、HEAD
- `mediacache-http-server-srp` — Wire/Router/Adapter 拆分

## 符号命名（2026-11-20 server 收尾）

| 区域 | 推荐命名 | 说明 |
|------|----------|------|
| Registry | `acceptConnection(connection)` | 替代 `handleConnection(cnt)` |
| Session I/O | `enqueueIoTask` / `mIoSerialChain` | 与同仓 asset 的 `enqueueTask` 区分 |
| Session 泵 | `pumpResponseBody` / `mBodyPumpActive` | 替代 `consumeData` / `mConsuming` |
| Session 生命周期 | `dispatchRequest` / `cancelCurrentResponse` / `handleDisconnect` | |
| ReceiveBuffer | `takeCompleteRequestHeaders` / `dropLeadingBytes` | |
| WireFormat | `encodeChunkedBodySegment` / `formatChunkedTerminator` | 与 `formatErrorResponse` 同前缀风格 |
| Adapter 状态 | `mFetcherExhausted` / `mChunkTerminatorSent` | |

## Session 状态机审查（逻辑不变式）

### 单连接字段

| 字段 | 含义 |
|------|------|
| `mCurrentResponse` | 当前在飞的 `IMCHttpResponse`，完成后置空以支持 keep-alive 下一请求 |
| `mHeadersSent` | 已向 socket 写出响应头 |
| `mBodyPumpActive` | 正有一次 `pumpResponseBody` 任务占住泵（防重入） |
| `mIoSerialChain` | 所有 `send` / `prepare` / 泵 串行排队 |

### 主路径

1. `handleTcpMessage` → `append` → `takeCompleteRequestHeaders` 循环。
2. 每条新请求：**先** `cancelCurrentResponse`（流水线/抢占上一响应）→ `parseRequest` → `dispatchRequest`。
3. `prepare` 成功 → `onResponseHeaders` 排队写头 → 非 HEAD 则 `pumpResponseBody`。
4. `read` 有数据则写 socket；未 `isDone` 则 `scheduleBodyPump` 或等 `newDataReadable`。
5. `onResponseDone` 清空当前响应，**不关 TCP**（keep-alive）。

### 失败路径（约定）

| 场景 | 行为 |
|------|------|
| 解析失败 / 缓冲超限 | `closeWithErrorStatus(400)` + 断连 |
| `prepare` 失败（未发头） | `disposeAfterPrepareFailure` + Session `closeWithErrorStatus(500)`，**不**走 `onSocketError` |
| 流式 `aborted`（未发头） | `onResponseAborted` → 500 |
| 流式 `aborted`（已发头） | `onSocketError` → 关连接 |
| 新请求到达 | `cancelCurrentResponse`，`aborted` 回调已 off 则不重复通知 |

### 已知限制（暂不改动）

- 入站带 body 的字节：解析拒绝 `Content-Length>0`，但若客户端仍发送 body，多余字节留在 `MCHttpReceiveBuffer`，可能影响同连接下一请求（本地代理场景极少）。
- HTTP 流水线：允许在上一响应未完成时解析下一请求头并取消上一响应（简化实现，非完整 RFC 流水线队列）。

### 问题清单

| 项 | 严重度 | 状态 |
|----|--------|------|
| `prepare` 失败同时 `failFromFetcher` + I/O 链 `onSocketError` 竞态 | 中 | **已修**（`disposeAfterPrepareFailure` + Session try/catch） |
| Session/Adapter 无 hypium 状态机单测 | 低 |  backlog |
| 头后残留 body 字节 | 低 | 文档化 |

## 日志示例行

```
[MCHttpConnectionSession] [clientId:3] Request GET /mc_proxy/... Range:bytes=0-
[MCHttpResponseAdapter] [clientId:3] prepare done status=206 chunked=false eos=false
```