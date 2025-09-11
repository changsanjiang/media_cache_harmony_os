import { MCMediaCache, } from '../../Index';

/** HLS variant 选择, 在多码率流中选择一个(比如高码率或低码率) */
@ComponentV2
export struct HlsVariantSelectionPage {
  private mPlaybackUrl: string = "";

  async aboutToAppear(): Promise<void> {
    // 初始化 MCMediaCache;
    // 请在 app 启动后初始化一次即可;
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    // 配置变体流选择器, 选择需要缓存的流(只能选择一个)
    // 同样在 app 启动后配置一次即可;
    //
    // 如以下内容:
    // #EXTM3U
    // #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
    // low.m3u8
    // #EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=1280x720
    // high.m3u8
    //
    // #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="English",LANGUAGE="en",URI="eng.m3u8"
    // #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="French",LANGUAGE="fr",URI="fre.m3u8"
    //
    // 其中:
    // - low.m3u8、high.m3u8 → Variant Streams（变体流，多码率视频）
    // - eng.m3u8、fre.m3u8 → Renditions（衍生流，如多语言音轨）
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
