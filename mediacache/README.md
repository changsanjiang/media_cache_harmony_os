# MediaCache for HarmonyOS

MediaCache 用于支持音视频边播放边缓存; 旨在代理媒体数据请求并优先提供缓存数据, 从而减少网络流量并提高播放流畅度.

目前支持以下两种类型的远程资源: 
- 基于文件的媒体，例如 MP3、AAC、WAV、FLAC、OGG、MP4 和 MOV 等常见格式;
- HTTP Live Streaming 或者叫 m3u8; 在播放时通常会自动代理播放列表中的各个媒体片段;

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

- 配置请求头:
  发起请求前回调, 可以在回调中修改请求, 添加请求头, cookies等;
  ```ts
  MCMediaCache.setRequestHandler((request) => {
    request.setHeader('key', 'value');
  });
  ```
- 数据加密:
  保存数据时加密; 缓存数据写入到文件时回调, 你可以对数据进行一些加密处理;
  ```ts
  MCMediaCache.setDataEncryptHandler(async (resUrl, dataOffset, data) => {
    // xxx
  });
  ```
- 数据解密:
  读取数据时解密; 读取数据时回调, 如果原数据被加密但是播放时需要解密, 你可以在该回调中进行解密处理;
  ```ts
  MCMediaCache.setDataDecryptHandler(async (resUrl, dataOffset, data) => {
    // xxx
  });
  ```
- 配置控制台日志:
  ```ts
  MCMediaCache.setLogEnabled(BuildProfile.DEBUG); // 是否开启日志;
  MCMediaCache.setLogLevel(MCLogLevel.DEBUG); // 设置日志等级;
  MCMediaCache.setLogWhiteModules([MCLogModule.MCHttpConnectionHandler, MCLogModule.MCHttpResponse]) // 允许打印哪些模块的日志;
  ```
- 缓存标识处理:
  由于相同的标识将引用同一份缓存, 当出现多个地址指向同一个视频, 例如 url 可能带有鉴权之类的参数, 这部分很容易发生变化, 但这些地址都指向同一个视频, 为了确保只缓存一份视频, 你可以在这里将这些会变化的参数移除;
  ```ts
  MCMediaCache.setAssetIdentifierPreprocessor(async (resUrl) => {
    const resUrl = 'http://xxx?token=xxx';
    const index = resUrl.indexOf('?');
    return index !== -1 ? resUrl.slice(0, index) : resUrl;
  });
  ```
  
#### 播放

使用代理地址进行播放; 在播放之前使用该方法生成代理地址:

