import { HLSDefines, MCMediaCache } from '../../Index';

@ComponentV2
export struct HlsRenditionSelectionPage {
  private mPlaybackUrl: string = "";

  async aboutToAppear(): Promise<void> {
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    // 设置 Rendition 选择逻辑
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
