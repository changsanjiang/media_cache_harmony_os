# 提案 vs 实现

| 提案项 | 实现（交付类名） | 状态 |
|--------|------------------|------|
| Wire 集中 200/206/400/500 + chunked | `MCHttpWireFormat` | ✓ |
| Router 唯一 Manager 依赖 | `MCHttpProxyRouter` | ✓ |
| Response 无 asset/exporter/virtual import | `MCHttpResponseAdapter` | ✓ |
| 连接状态机独立文件 | `MCHttpConnectionSession` + `MCHttpConnectionRegistry` | ✓ |
| transport-fixes 行为保持 | 缓冲/HEAD/omitsResponseBody 未改语义 | ✓ |

## 收尾（同次提交）

| 项 | 状态 |
|----|------|
| 类重命名（Registry/Session/Adapter/ProxyRouter/WireFormat） | ✓ |
| `MCLogger.withClient` + `MCHttpLog.summarizeRequest` | ✓ |
| 单测 `MCHttpWireFormat.test.ets` | ✓ |
| `.cursor/skills/mediacache-module-refine` | ✓ |

## 回归

- [ ] MP4 GET Range 播放
- [ ] HEAD 无 body
- [ ] 非法请求 400
- [ ] INFO 白名单下日志可读、无逐 chunk 刷屏