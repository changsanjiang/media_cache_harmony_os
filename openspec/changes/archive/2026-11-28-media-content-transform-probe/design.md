## D1: 单一 probe 路径

所有 `MCMedia` 使用同一 `MCDownload` 请求：`Range: bytes=0-1`，应用 `MCConfigs.requestHandler` 与 `proxyRequest.headers`。

## D2: 改写类 metadata

当 `mContentTransformer` 存在时：

- 允许 HTTP **200 或 206**（探测与 Loader 的「仅 200」分离）。
- **不得**使用 `Content-Range` / `Content-Length` 作为最终 `totalLength`。
- 占位：`totalLength = Number.MAX_SAFE_INTEGER`，`byteRangeAccessSupported = false`。
- `saveMetadata` 与现网 FILE 探测一致立即落盘。

## D3: 非改写类

保持原有逻辑：从响应头推导 `byteRangeAccessSupported` 与 `totalLength`（含 `content-range`）。

## D4: fetch / resolve

不变：`resolve` 在 `byteRangeAccessSupported === false` 时仍选择 `MCMediaProxyContentLoader`；`finalize` 写入真实长度。

## D5: prepare 默认清理占位 content

`MCMediaContentProvider.prepare` 在 `totalLength === MAX_SAFE_INTEGER` 时默认删除该 media 目录下不可信 `c_*` 文件（不区分是否 contentTransformer）。

## D6: 空资源 probe

`inferProbeEmptyTotalLength`：416、`Content-Length: 0`、`Content-Range` 总长 0、200 且空 body；改写与非改写均落 `totalLength: 0`，不走占位与整包 Loader。