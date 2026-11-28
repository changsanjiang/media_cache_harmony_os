## Why

带 `contentTransformer` 的清单类媒体在 `probe` 中会整包 GET、改写并写盘，与 `MCMediaTransformContentLoader` 重复；本地 HEAD 也会触发整包拉取。部分 CDN 不支持 HEAD，需与 FILE 媒体一致用 `Range: bytes=0-1` 探测。

## What Changes

- 删除 `probe` 内「整包下载 + 改写」分支；改写仅在 `MCMediaTransformContentLoader` 完成。
- 统一 `probe`：`bytes=0-1`，接受 **200/206**；改写类仅取 `Content-Type`，占位 `totalLength = MAX_SAFE_INTEGER`、`byteRangeAccessSupported = false` 并落盘。
- 删除 `mContentTransformer` 在通用 probe 路径上的死代码（强制 200 等）。

## Capabilities

### New Capabilities

- `mediacache-content-transform-probe`: 清单改写媒体的轻量探测与占位元数据语义。

### Modified Capabilities

- （无既存 spec 措辞变更）

## Impact

- `media/MCMedia.ets`
- `docs/ARCHITECTURE.md`（probe 行为说明）

## Non-goals

- 合并 `MCMediaTransformContentLoader` 与 `RemoteContentLoader`；`lengthPending` 新字段。