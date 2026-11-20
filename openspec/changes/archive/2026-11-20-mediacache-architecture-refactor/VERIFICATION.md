# 手工回归清单

- [ ] `MCMediaCache.prepare` 后 entry **Test AVPlayer** 播放 MP4/HLS 代理 URL
- [ ] 对 DASH MPD 调用 `MCMediaCache.prefetch`（此前为 Unsupported type）
- [ ] 播放中触发 `cacheConfig.maxDiskSize` 缩小，确认未被强制 `abort` 删盘（in-use 跳过）
- [ ] `exportToDirectory` 对 DASH 应抛出明确「不支持导出」错误