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

## 日志示例行

```
[MCHttpConnectionSession] [clientId:3] Request GET /mc_proxy/... Range:bytes=0-
[MCHttpResponseAdapter] [clientId:3] prepare done status=206 chunked=false eos=false
```