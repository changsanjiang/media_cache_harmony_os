# 提案 vs 实现对照

| 提案项 | 实现 | 状态 |
|--------|------|------|
| 连接级 `MCHttpReceiveBuffer`，按 `\r\n\r\n` 拆请求 | `MCHttpReceiveBuffer.ets` + `MCHttpConnectionHandler` while 循环 | ✓ |
| 最大头部长度限制 | 默认 64KiB，`append` 抛错 → 400 关连接 | ✓ |
| `IMCDataRequest.method` GET/HEAD | `defines/IMCDataRequest.ets`，`MCHttpResponse.toDataRequest` | ✓ |
| HEAD：probe + 响应头、无 body | `MCMedia.buildHeadOnlyResponse` + `composeDataResponse`；`omitsResponseBody` 跳过 `consumeData` | ✓ |
| 入站 body：`Content-Length > 0` 拒绝 | `parseRequest` | ✓ |
| Virtual 资源 HEAD | `MCVirtualResourceDataFetcher.headersForContent` | ✓ |
| 单测 | `MCHttpReceiveBuffer.test.ets` | ✓ |
| Non-goals（HTTP/2、pipeline 队列） | 未实现 | 按设计 |

# 代码审计备忘

- HEAD 元数据以 **`probe` 返回值** 传入 `buildHeadOnlyResponse`，避免 `mMetadata!` 隐式约定。
- GET/HEAD 响应形状由 **`composeDataResponse`** 统一，与 `resolve` 共用，避免分支漂移。
- `mProxyHandler` 路径下 HEAD 仍会经 `probe` 触发整包 GET（既有行为，未在本 change 优化）。

# 手工回归清单

- [ ] 半包：分两段 TCP 发送同一 GET 请求头，连接不应 400
- [ ] 粘包：连续两条 GET/HEAD 在同一 `message`，两条均被处理
- [ ] HEAD `/mc_proxy/...`：有 `Content-Length`、无响应体
- [ ] GET 播放 MP4/HLS 与变更前一致
- [ ] `/mc_virtual_proxy/...` HEAD 与 GET 头字段一致（无 body）