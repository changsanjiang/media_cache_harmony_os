# MediaCache for HarmonyOS

MediaCache 主要用于支持音视频的边播放边缓存; 旨在代理媒体数据请求并优先提供缓存数据, 从而减少网络流量并提高播放流畅度.

目前支持以下两种类型的远程资源: 
- 基于文件的媒体，例如 MP3、AAC、WAV、FLAC、OGG、MP4 和 MOV 等常见格式;
- HTTP Live Streaming 或者叫 m3u8; 在播放时通常会自动代理播放列表中的各个媒体片段;

支持预缓存;

#### 安装
```shell
ohpm i @sj/mediacache
```

#### 在项目中引用

请在需要依赖的模块找到 oh-package.json5 文件, 新增如下依赖, 执行同步后等待安装完成;
```json
{
  "dependencies": {
    "@sj/mediacache": "^1.0.0"
  }
}
```

#### 基础配置

- 配置请求头: 发起请求前回调, 可以在回调中修改请求, 添加请求头, cookies等;
  ```ts
  MCMediaCache.setRequestHandler((request) => {
    request.setHeader('key', 'value');
  });
  ```
- 数据加密: 保存数据时加密; 缓存数据写入到文件时回调, 你可以对数据进行一些加密处理;
  ```ts
  MCMediaCache.setDataEncryptHandler(async (resUrl, dataOffset, data) => {
    // xxx
  });
  ```
- 数据解密: 读取数据时解密; 读取数据时回调, 如果原数据被加密但是播放时需要解密, 你可以在该回调中进行解密处理;
  ```ts
  MCMediaCache.setDataDecryptHandler(async (resUrl, dataOffset, data) => {
    // xxx
  });
  ```
- 缓存标识处理: 由于相同的标识将引用同一份缓存, 当出现多个地址指向同一个视频, 例如 url 可能带有鉴权之类的参数, 这部分很容易发生变化, 但这些地址都指向同一个视频, 为了确保只缓存一份视频, 你可以在这里将这些会变化的参数移除;
  ```ts
  MCMediaCache.setAssetIdentifierPreprocessor(async (resUrl) => {
    const resUrl = 'http://www.example.com/video.mp4?token=xxx';
    const index = resUrl.indexOf('?');
    return index !== -1 ? resUrl.slice(0, index) : resUrl;
  });
  ```
- 缓存管理:
  - 个数限制: 可以配置缓存个数, 超过限制时将会自动删除旧的缓存:
    ```ts
    // 缓存个数限制: 0 表示不限制;
    MCMediaCache.cacheConfig.countLimit = 0;
    ```
  - 保存时长限制(单位: 毫秒): 超过限制自动删除;   
    ```ts
    // 保存时长限制(单位: 毫秒): 0 表示不限制;
    MCMediaCache.cacheConfig.maxAge = 0;
    ```
  - 所有缓存能够占用的磁盘大小(单位: 字节): 超过限制时将会自动删除旧的缓存;
    ```ts
    // 磁盘空间限制(单位: 字节): 0 表示不限制;
    MCMediaCache.cacheConfig.maxDiskSize = 0;
    ```
  - 磁盘空间预警阈值(单位: 字节): 当磁盘剩余空间不足小于预警阈值时将会自动删除旧的缓存:
    ```ts
    // 磁盘空间预警阈值(单位: 字节): 0 表示不限制;
    MCMediaCache.cacheConfig.diskSpaceWarningThreshold = 0;
    ```
- 配置控制台日志:
  ```ts
  MCMediaCache.setLogEnabled(BuildProfile.DEBUG); // 是否开启日志;
  MCMediaCache.setLogLevel(MCLogLevel.DEBUG); // 设置日志等级;
  MCMediaCache.setLogWhiteModules([MCLogModule.MCHttpConnectionHandler, MCLogModule.MCHttpResponse]) // 允许打印哪些模块的日志;
  ```
      
#### 初始化

在开始代理请求之前, 请通过以下方法进行初始化工作以启动代理服务器等;
```ts
await MCMediaCache.prepare();
```

#### 播放

播放时需要通过代理地址进行播放; 所以在播放之前请使用该方法生成代理地址, 然后设置给播放器播放即可:
```ts
// 原始地址
const resUrl = 'http://www.example.com/video.mp4';
// 代理地址
const proxyUrl = await MCMediaCache.proxy(resUrl);

// 设置播放; 这里以 AVPlayer 为例, 直接设置代理地址播放即可实现边播放边缓存;
const player: media.AVPlayer;
player.url = proxyUrl;
```

#### 预缓存

- 预先缓存指定大小的数据:
  ```ts
  // 直接使用原始地址进行预缓存即可;
  MCMediaCache.prefetch(resUrl, {
    prefetchSize: 5 * 1024 * 1024, // 假设预缓存5M
    onProgress: (progress) => console.log(`[progress] ${progress}`)
  });
  ```
- 预先缓存指定数量的媒体片段: 这个配置主要用于流媒体(HLS), 因为它的播放列表(playlist)中通常包含多个段(ts)文件, 通过以下配置来指定需要预缓存的文件数;
  ```ts
  // 直接使用原始地址进行预缓存即可;
  MCMediaCache.prefetch(resUrl, {
    prefetchSegmentCount: 1, // 假设预缓存1个片段
    onProgress: (progress) => console.log(`[progress] ${progress}`)
  });
  ```