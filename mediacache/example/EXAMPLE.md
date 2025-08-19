# MCMediaCache Examples

本目录提供了一些典型的示例代码，帮助开发者快速上手使用 `MCMediaCache`;

___

#### 目录结构
```
examples/
├── EXAMPLE.md                          # 说明如何运行 examples，以及每个 example 的用途
├── basic/
│   ├── ProxyPlayPage.ets               # 代理播放示例
│   └── PrefetchPage.ets                # 预缓存示例
|   └── ExportPage.ets                  # 导出到指定目录 + 并代理该目录进行播放示例
├── advanced/
│   ├── CustomRequestPage.ets           # 自定义请求头
│   ├── EncryptDecryptPage.ets          # 加解密处理
│   └── IdentifierPreprocPage.ets       # 资产标识预处理
└── hls/
    ├── HlsVariantSelectionPage.ets     # HLS variant 选择, 在多码率流中选择一个(比如高码率或低码率)
    └── HlsRenditionSelectionPage.ets   # HLS rendition 选择, 在音轨/字幕等多 renditions 中选择一个(比如选择西班牙语音轨，或者英语字幕)
```

___
