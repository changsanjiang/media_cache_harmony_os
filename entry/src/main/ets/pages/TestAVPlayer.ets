import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';

class CustomXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    console.log(`onSurfaceCreated surfaceId: ${surfaceId}`);
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    console.log(`onSurfaceChanged surfaceId: ${surfaceId}, rect: ${JSON.stringify(rect)}}`);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    console.log(`onSurfaceDestroyed surfaceId: ${surfaceId}`);
  }
}


@Entry
@Component
struct VideoPlayer2 {
  xComponentController: XComponentController = new CustomXComponentController();
  private url: string =  (router.getParams() as Record<string, string>)['url'];
  avPlayer?: media.AVPlayer = undefined;
  @State progressValue: number = 0    // 设置进度条初始值为0

  aboutToDisappear(): void {
    this.avPlayer?.stop();
    this.avPlayer?.release();
  }

  build(){
    Column() {
      Text("TestAVPlayer")
        .id('TestAVPlayer')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })

      XComponent({
        type: XComponentType.SURFACE,
        controller: this.xComponentController,
      }).width('100%').aspectRatio(16/9);

      Slider({
        value: this.progressValue,
        min: 0,
        max: 100
      }).onChange((value: number, mode: SliderChangeMode) => {
        if ( this.avPlayer && mode === SliderChangeMode.End ) {
          this.avPlayer.seek(value / 100 * this.avPlayer.duration);
        }
      })

      Row().width('100%').height(5)

      Row() {
        Button("快退-15")
          .onClick(()=>{
            if ( this.avPlayer ) {
              this.avPlayer.seek(Math.max(this.avPlayer.currentTime - 15000, 0));
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
            if ( this.avPlayer ) {
              this.avPlayer.seek(Math.min(this.avPlayer.currentTime + 15000, this.avPlayer.duration * 0.98));
            }
          })
      }
    }
  }

  private async play() {
    if ( !this.avPlayer ) {
      // 创建avPlayer实例对象
      this.avPlayer = await media.createAVPlayer();
      // startRenderFrame首帧渲染回调函数
      this.avPlayer.on('startRenderFrame', () => {
        console.info(`AVPlayer start render frame`);
      })
      // seek操作结果回调函数
      this.avPlayer.on('seekDone', (seekDoneTime: number) => {
        console.info(`AVPlayer seek succeeded, seek time is ${seekDoneTime}`);
      })
      // error回调监听函数,当avPlayer在操作过程中出现错误时调用reset接口触发重置流程
      this.avPlayer.on('error', (err: BusinessError) => {
        console.error(`Invoke avPlayer failed, code is ${err.code}, message is ${err.message}`);
        this.avPlayer!.reset(); // 调用reset重置资源，触发idle状态
      })
      // 状态机变化回调函数
      this.avPlayer.on('stateChange', async (state: string, reason: media.StateChangeReason) => {
        switch (state) {
          case 'idle': // 成功调用reset接口后触发该状态机上报
            console.info('AVPlayer state idle called.');
            this.avPlayer!.release(); // 调用release接口销毁实例对象
            break;
          case 'initialized': // avplayer 设置播放源后触发该状态上报
            console.info('AVPlayer state initialized called.');
            this.avPlayer!.surfaceId = this.xComponentController.getXComponentSurfaceId(); // 设置显示画面，当播放的资源为纯音频时无需设置
            this.avPlayer!.prepare();
            break;
          case 'prepared': // prepare调用成功后上报该状态机
            console.info('AVPlayer state prepared called.');
            this.avPlayer!.play(); // 调用播放接口开始播放
            break;
          case 'playing': // play成功调用后触发该状态机上报
            console.info('AVPlayer state playing called.');
            break;
          case 'paused': // pause成功调用后触发该状态机上报
            console.info('AVPlayer state paused called.');
            break;
          case 'completed': // 播放结束后触发该状态机上报
            console.info('AVPlayer state completed called.');
            this.avPlayer!.seek(0); //调用播放结束接口
            break;
          case 'stopped': // stop接口成功调用后触发该状态机上报
            console.info('AVPlayer state stopped called.');
            this.avPlayer!.reset(); // 调用reset接口初始化avplayer状态
            break;
          case 'released':
            console.info('AVPlayer state released called.');
            this.avPlayer = undefined;
            break;
          case 'error': {
            console.info('AVPlayer state error called.');
            this.avPlayer?.release();
          }
            break;
          default:
            console.info('AVPlayer state unknown called.');
            break;
        }
      })

      this.avPlayer.on('timeUpdate', (time) => {
        this.progressValue = time / this.avPlayer!.duration * 100;
      });

      this.avPlayer.url = this.url;
    }
    else {
      this.avPlayer.play();
    }
  }

  private pause() {
    this.avPlayer?.pause();
  }
}