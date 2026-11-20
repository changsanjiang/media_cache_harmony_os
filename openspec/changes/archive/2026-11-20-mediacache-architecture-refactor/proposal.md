## Why

MediaCache 的 Asset → Media → Fetcher 分层合理，但播放/预取/导出在 Manager 层分叉、生命周期绑定在多层 Fetcher、淘汰策略不识别「使用中」资源，导致 DASH 能力未闭环、架构债与逻辑 bug 交织。需要在**不破坏对外 `MCMediaCache` API** 的前提下，显式固化领域边界并统一扩展点，再系统性修逻辑问题。

## What Changes

- 引入**设计不变式**与 **Asset 能力表**（FILE/HLS/DASH × play / prefetch / export / localPlay），统一三入口的解析与分发。
- 引入 **RequestScope**：一次代理 HTTP 请求持有 `readwriteRetain/Release`，Fetcher 退化为会话适配层。
- 引入 **CachePolicy**：淘汰前查询 in-use（ref > 0）与 pin，禁止强行 `abort`+删盘正在服务的 Asset。
- 收敛 Fetcher：**保留** `IMCDataFetcher` 作为 HTTP 会话接口；**合并** AssetDataFetcher 与 MediaDataFetcher 的职责到 `MCMediaHttpSession`（或等价命名），`MCHttpResponse` 只委托 Session。
- **Non-goals（本 change 不做）**：`MCMediaCacheContext` 全量替代 `MCConfigs`、完整 DASH 导出/本地播、TCP 半包缓冲、HEAD 语义、全量单测矩阵。

## Capabilities

### New Capabilities

- `mediacache-domain`: Asset/Media 不变式、能力矩阵、类型扩展契约。
- `mediacache-http-session`: 代理播放的 HTTP 会话层（prepare/read/abort）与 RequestScope。
- `mediacache-cache-policy`: 缓存淘汰、pin、in-use 门禁与访问日志协作。

### Modified Capabilities

（无既有 openspec spec；行为变更以新 spec 为基线，对外 API 保持兼容。）

## Impact

- `mediacache/src/main/ets/src/server/`（MCHttpResponse、ConnectionHandler 间接）
- `mediacache/src/main/ets/src/asset/`、`session/MCMediaHttpSession.ets`（生命周期、能力表）
- `mediacache/src/main/ets/src/asset/cachemgr/MCAssetCacheManager.ets`
- `mediacache/src/main/ets/src/prefetcher/MCAssetPrefetchManager.ets`
- `mediacache/src/main/ets/src/exporter/MCAssetExportManager.ets`
- `mediacache/src/main/ets/src/defines/`（新接口）
- `docs/ARCHITECTURE.md`（与 spec 对齐）

## Implementation Priority (Phases)

| 阶段 | 内容 | 价值 |
|------|------|------|
| **P0** | 领域 spec + 能力表 + `IMCAssetCapabilities` | 统一扩展点，接入 DASH prefetch |
| **P1** | RequestScope + CachePolicy in-use 门禁 | 修复播放中被淘汰类架构根因 |
| **P2** | `MCMediaHttpSession` 收敛 Fetcher | 减重复 abort/retain |
| **P3** | Prefetch/Export 走能力表 | 清 Manager 层 switch 重复 |
| **P4** | 单测与 entry 回归 | 防回归 |