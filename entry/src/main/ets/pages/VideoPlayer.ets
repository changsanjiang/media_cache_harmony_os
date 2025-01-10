import { MCMediaCache } from '@sj/mediacache';

@Entry
@Component
struct VideoPlayer {
  private controller: VideoController | undefined;
  private previewUris: Resource = $r ('app.media.background');

  private videoSrc: string = 'https://xy2.v.netease.com/2020/dhp/eqokwojw16.mp4' // 使用时请替换为实际视频加载网址
  @State
  private proxyUrl: string = this.videoSrc;

  async aboutToAppear(): Promise<void> {
    this.proxyUrl = await MCMediaCache.proxy(this.videoSrc);
  }

  build(){
    Column() {
      Text("VideoPlayer")
        .id('VideoPlayer')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })

      Video({
        src: this.proxyUrl,
        previewUri: this.previewUris,
        controller: this.controller
      })
        .height('60%')
        .objectFit(ImageFit.Fill)
        .onError(() => {
        console.error(`AAAA: player on Error!`);
      })
    }
  }
}