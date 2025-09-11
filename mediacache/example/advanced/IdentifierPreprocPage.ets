import { MCMediaCache } from '../../Index';

/** 资产标识预处理 */
@ComponentV2
export struct IdentifierPreprocPage {
  private mPlaybackUrl: string = '';

  async aboutToAppear(): Promise<void> {
    // 初始化 MCMediaCache;
    // 请在 app 启动后初始化一次即可;
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    // 去除 URL 中的鉴权参数，避免缓存重复
    // 在 app 启动后配置一次即可;
    MCMediaCache.setAssetIdentifierPreprocessor(async (url: string) => {
      /**
       * 例如:
       *  A: "https://example.com/video/test.mp4?token=abc123&user=xyz";
       *  B: "https://example.com/video/test.mp4?token=def456&user=bar";
       *
       * 这两个 url 都指向同一个视频, 但参数 query 部分不同;
       * 此时可以将 query 部分移除, 这样就可以引用同一份缓存;
       * */
      const cleanUrl = url.split("?")[0];
      console.info(`Preprocessed asset identifier: ${cleanUrl}`);
      return cleanUrl;
    });

    const resUrl = "https://example.com/video/test.mp4";
    this.mPlaybackUrl = await MCMediaCache.proxy(resUrl);
  }

  build() {
    Video({ src: this.mPlaybackUrl })
      .height("60%")
      .objectFit(ImageFit.Fill)
  }
}
