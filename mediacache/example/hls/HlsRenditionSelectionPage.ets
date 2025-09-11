import { HLSDefines, MCMediaCache } from '../../Index';

/** HLS rendition 选择, 在音轨/字幕等多 renditions 中进行选择(比如选择英语音轨，英语字幕) */
@ComponentV2
export struct HlsRenditionSelectionPage {
  private mPlaybackUrl: string = "";

  async aboutToAppear(): Promise<void> {
    // 初始化 MCMediaCache;
    // 请在 app 启动后初始化一次即可;
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    // 配置衍生流选择器, 选择需要缓存的流(同一种类型只能选择一个流)
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
    MCMediaCache.setRenditionSelectionHandler((playlistOriginalUrl, playlistCurrentUrl, renditionGroup, renditionType) => {
      console.info(`[HLS Rendition] playlistOriginalUrl=${playlistOriginalUrl}, type=${renditionType}, groupId=${renditionGroup.groupId}`);

      if (renditionType === HLSDefines.RenditionType.AUDIO) {
        // 例如：优先选择西班牙语音轨
        const es = renditionGroup.renditions.find(item => item.language === "es");
        if (es) {
          console.info(`[HLS Rendition] chosen Spanish audio`);
          return es;
        }
      }

      if (renditionType === HLSDefines.RenditionType.SUBTITLES) {
        // 例如：优先选择英语字幕
        const en = renditionGroup.renditions.find(item => item.language === "en");
        if (en) {
          console.info(`[HLS Rendition] chosen English subtitles`);
          return en;
        }
      }

      // 默认返回第一个
      console.info(`[HLS Rendition] fallback chosen ${renditionGroup.renditions[0].name}`);
      return renditionGroup.renditions[0];
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
