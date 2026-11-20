## Context

MediaCache 采用 Asset → Media → ContentLoader 分层（ refactor 前：播放经 `MCAssetDataFetcher`，预取/导出多处 `switch`，淘汰不识别 in-use）。**实施后**：`MCMediaHttpSession`、 `MCAssetCapabilityRegistry`、`MCCachePolicy`。

约束：保持 `MCMediaCache` 公共 API 与代理 URL 形态不变；HarmonyOS ArkTS；渐进式重构。

## Goals / Non-Goals

**Goals:**

- 显式 **能力矩阵** 与 **Registry**，三种 Asset 类型在同一扩展点注册 play/prefetch/export。
- **RequestScope** 统一管理单次 HTTP 请求对 Asset/Media 的 retain/release。
- **CachePolicy** 在淘汰路径上尊重 in-use 与 pin。
- 新建 **MCMediaHttpSession** 作为唯一播放会话；已删除 `MCAssetDataFetcher`。

**Non-Goals:**

- DASH `exportToDirectory` / `MCLocalDashAsset` 完整实现。
- TCP 请求缓冲、HEAD 无 body、全链路 `MCMediaCacheContext` 替代 `MCConfigs`。

## Decisions

### D1: 能力表 `MCAssetCapabilities` + `MCAssetCapabilityRegistry`

- **Decision**: 静态注册 `MCAssetType` → `{ supportsPrefetch, supportsExport, supportsLocalPlay, createPrefetcher?, createExporter? }`。
- **Rationale**: 消除三处 switch 不一致（DASH prefetch 已实现类但未接入）。
- **Alternative**: 能力方法挂在 `IMCAsset` 上 —— 会增加 Asset 子类体积，且预取器/导出器非 Asset 实例方法更合适。

### D2: `MCRequestScope` 包装 retain/release

- **Decision**: `MCRequestScope.acquire(asset)` / `release()` 在 finally 中配对；`MCMediaHttpSession` 构造时 acquire，`abort`/`done` 时 release。
- **Rationale**: 单点所有权，便于 CachePolicy 查询 `asset.readwriteCount` 或专用 `inUse` 计数。
- **Alternative**: 仅在 CacheManager 查 Map<clientId, assetId> —— 与预取路径不一致。

### D3: `MCCachePolicy.canEvict(assetId)`

- **Decision**: `evictAssets` 前若 `MCAssetManager.isAssetInUse(assetId)` 为 true 则跳过；pin 逻辑保留。
- **Rationale**: 最小改动修复 P0 架构缺陷。
- **Alternative**: 软删除标记 —— 更大迁移，后续可做。

### D4: `MCMediaHttpSession` 合并会话 Fetcher

- **Decision**: 播放会话由 `MCMediaHttpSession` 包装 `MCMediaDataFetcher`；`MCHttpResponse` 对 `/mc_proxy` 与 `/mc_dir_proxy` 直接 `new MCMediaHttpSession(...)`。
- **Rationale**: 一层 abort/read；Asset 只做 `getMediaByProxyPath`。
- **Alternative**: 保留两个类，仅抽公共基类 —— 收益较小。

### D5: 迁移顺序

P0 能力表 + DASH prefetch 接线 → P1 Scope + Policy → P2 HttpSession → P3 PrefetchManager/ExportManager 改用 Registry。

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| 会话层与 MediaDataFetcher 双层 retain | 设计约定：Session 持 Asset，MediaDataFetcher 持 Media |
| in-use 仅依赖 readwriteCount，预取也 retain | 预取已 finally release；文档注明 |
| Registry 静态表难以单测注入 | 预留 `setRegistryForTest` 或 package 内可替换 |

## Migration Plan

1. 新增 defines + policy + session，不改入口。
2. 切换 `MCHttpResponse` 至 Session（行为等价测试：entry 播放）。
3. PrefetchManager 改 Registry；接入 DashAssetPrefetcher。
4. 更新 `docs/ARCHITECTURE.md`；`openspec archive` 后主 spec 落入 `openspec/specs/`。

## Open Questions

- `MCAssetManager` 是否暴露 `isAssetInUse` 仅查内存 map 中 asset 的 count，还是包含 prefetch 进行中的全局注册？**首版：仅 `IMCAsset.readwriteCount > 0` 且存在于 map。**