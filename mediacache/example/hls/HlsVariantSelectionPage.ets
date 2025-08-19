import { MCMediaCache, } from '../../Index';

@ComponentV2
export struct HlsVariantSelectionPage {
  private mPlaybackUrl: string = "";

  async aboutToAppear(): Promise<void> {
    // 初始化 MCMediaCache;
    // 请在 app 启动后初始化一次即可;
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    MCMediaCache.setVariantStreamSelectionHandler((playlistOriginalUrl, playlistCurrentUrl, variantStreams) => {
      console.info(`[HLS Variant] playlistOriginalUrl=${playlistOriginalUrl}, found=${variantStreams.length}`);

      // 简单策略：选择最高分辨率的流
      const sorted = [...variantStreams].sort((a, b) => b.bandwidth - a.bandwidth);
      const chosen = sorted[0];
      console.info(`[HLS Variant] chosen=${chosen.resolution} @${chosen.bandwidth}`);
      return chosen;
    });

    // 示例 HLS master playlist
    const masterUrl = "https://example.com/master.m3u8";
    this.mPlaybackUrl = await MCMediaCache.proxy(masterUrl);
  }

  build() {
    Video({ src: this.mPlaybackUrl })
      .height("60%")
      .objectFit(ImageFit.Fill)
  }
}
