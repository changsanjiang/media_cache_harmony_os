## 手动验证

1. **HLS master**：`MCMediaCache.proxy` 后播放；首次请求仅短 Range 探针，清单经本地代理返回改写后的 m3u8；分片可走代理缓存。
2. **HEAD**：对 playlist 代理 URL 发 HEAD；应对 CDN 发 `0-1` 而非整包 GET；无响应体。
3. **DASH MPD**：同上，MPD 改写后 BaseURL 指向 based_proxy。
4. **FILE mp4**：行为与改前一致（206/Range 探测、分片缓存）。

## 回归注意

- 冷启动：`prepare` 加载占位 metadata（`MAX_SAFE_INTEGER`）且无 content 时，首次 GET 仍走 `MCMediaProxyContentLoader`。
- `finalize` 后 metadata 更新为真实长度与 `byteRangeAccessSupported: true`。
- 空对象：`bytes=0-1` 返回 416 或 `Content-Length: 0` 时 `totalLength` 为 0，`prepare` 标记 assembled，无 Loader。