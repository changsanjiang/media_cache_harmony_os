import { router } from '@kit.ArkUI';

@Entry
@Component
struct VideoPlayer {
  private controller: VideoController | undefined;
  private previewUris: Resource = $r ('app.media.background');

  private url: string =  (router.getParams() as Record<string, string>)['url'];

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
        src: this.url,
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