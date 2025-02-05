import { IjkMediaPlayer } from "@ohos/ijkplayer";
import type { OnCompletionListener } from "@ohos/ijkplayer";
import { router } from "@kit.ArkUI";

@Entry
@Component
struct VideoPlayer3 {
  private url: string =  (router.getParams() as Record<string, string>)['url'];

  player?: IjkMediaPlayer = undefined;
  @State progressValue: number = 0    // 设置进度条初始值为0

  aboutToDisappear(): void {
    this.player?.stop();
    this.player?.release();
  }

  build(){
    Column() {
      Text("TestIJKPlayer")
        .id('TestIJKPlayer')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })

      XComponent({
        id: 'xcomponentId',
        type: 'surface',
        libraryname: 'ijkplayer_napi'
      }).onLoad((event?: object) => {
        if ( !this.mContext ) {
          this.mContext = event;
        }
      })
        .width('100%')
        .aspectRatio(16/9)
        .id('xcomponentId')

      Slider({
        value: this.progressValue,
        min: 0,
        max: 100
      }).onChange((value: number, mode: SliderChangeMode) => {
        if ( this.player && mode === SliderChangeMode.End ) {
          this.player.seekTo((value / 100 * this.player.getDuration()).toString());
        }
      })

      Row().width('100%').height(5)

      Row() {
        Button("快退-15")
          .onClick(()=>{
            if ( this.player ) {
              this.player.seekTo(Math.max(this.player.getCurrentPosition() - 15000, 0).toString());
            }
          })

        Button("播放")
          .onClick(()=>{
            this.play();
          })

        Button("暂停")
          .onClick(()=>{
            this.pause();
          })

        Button("快进+15")
          .onClick(()=>{
            if ( this.player ) {
              this.player.seekTo(Math.min(this.player.getCurrentPosition() + 15000, this.player.getDuration() * 0.98).toString());
            }
          })
      }
    }
  }

  @State mContext: object | undefined = undefined;

  private async play() {
    console.log(`play()`);

    try {
      if ( !this.player ) {
        this.player =  new IjkMediaPlayer();
        this.player.setContext(this.mContext, 'xcomponentId');
        this.player.setDebug(false);
        this.player.native_setup();
        this.player.setDataSource(this.url);
        this.player.setScreenOnWhilePlaying(true);

        const self = this;
        let mOnCompletionListener: OnCompletionListener = {
          onCompletion() {
            self.progressValue = 100;
            self.stopProgressTask();
            self.player?.seekTo("0");

            console.log(`IJKPlayer OnCompletion`);
          }
        }
        this.player.setOnCompletionListener(mOnCompletionListener);

        this.player.setMessageListener();
        this.player.prepareAsync();
        this.player.start();
      }
      else {
        this.player.start();
      }

      this.startProgressTask();
    } catch (error) {
      console.error(`error=${(error as Error).message}, ${error.stack}`)
    }
  }

  private pause() {
    this.player?.pause();
    this.stopProgressTask();

    console.log(`pause()`);

  }

  @State updateProgressTimer: number = 0;

  private startProgressTask() {
    this.updateProgressTimer = setInterval(() => {
      if ( this.player ) {
        if ( this.player.getDuration() > 0 ) {
          this.progressValue = this.player.getCurrentPosition() / this.player.getDuration() * 100;
        }
      }
      else {
        this.stopProgressTask();
      }
    }, 300);
  }

  private stopProgressTask() {
    clearInterval(this.updateProgressTimer);
  }
}