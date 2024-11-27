import { IMCMedia } from '../defines/IMCMedia';

namespace MCAssetManager {
  export function getMediaBy(proxyRequestTarget: string): Promise<IMCMedia> {
    throw new Error("Method not implemented.");
  }
}

export default MCAssetManager;

// @protocol MCSResponse <NSObject>
// @property (nonatomic, readonly) NSUInteger totalLength;
// @property (nonatomic, readonly) NSRange range; // 206请求时length不为0
// @property (nonatomic, copy, readonly) NSString *contentType; // default is "application/octet-stream"
// @end

// TODO: next ... data reader 如何读取数据?

/**
 * 一个地址指向一个媒体
 *
 * 比如
 *
 * File-based medias: mp3, mp4, wav ...
 * HLS medias: playlist(Media1), ts(Media2), key(Media3), variant stream(Media4),  rendition(Media6) ...

 Media metadata:
  - mime type
  - total length
  - random access flag

 现在是已经有一个代理请求了, 如何拿着这个请求去获取数据？ 从谁上面获取？

 // MCMediaDataReader

 // MCMedia

 内容都在 Media 中, Media 通过请求返回对应内容数组， 提供给 Reader 读取;

 内容数组可以是以下两者的组合：
 - 本地缓存内容
 - http内容

 如何获取一个 Media？

 proxyRequest 中必须携带足够的信息用于定位到哪个 Media;
  - media = MCAssetManager.getMediaBy(proxyRequest);
 然后 Media 通过请求返回对应内容数组， 提供给 Reader 读取;
  - media.getContentsBy(request);

 可能需要转换 proxyRequest to MCMediaDataReadRequest;


  不能返回内容， 得返回内容加载器， 用来加载内容， Reader 进行读取; ==> MCMediaContentLoader;

 Media 元数据的加载是通过 content loader 间接完成的, 所以当 content loader 的 dataLoaded 回调时, Reader 就可以直接读取这些元数据了;

 * AVAsset 核心功能
 资源封装： AVAsset 表示一个静态的多媒体资源（例如视频文件、音频文件、远程流等）。
 元数据提取： 可以获取资源的元数据（例如标题、作者、描述等）。
 轨道管理： 可以获取音频、视频、字幕等不同类型的轨道。
 资源分析： 不需要解码的情况下分析文件的时间范围、格式等。

 // - MCFileBasedAsset
 // - MCHLSAsset
 * */