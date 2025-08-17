import { MCLogLevel, MCLogModule, MCMediaCache } from '@sj/mediacache';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import BuildProfile from 'BuildProfile';
import { MCCopyFileConflictStrategy } from '@sj/mediacache/src/main/ets/src/defines/MCCopyFileConflictStrategy';

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State prefetchState: string = 'Test Prefetch';
  @State exportState: string = '畅江月';

  aboutToAppear() {
    // Asset 个数限制; 0 表示不限制;
    // MCMediaCache.cacheConfig.countLimit: number = 0;

    // Asset 保存时长限制(单位: 毫秒); 0 表示不限制;
    // MCMediaCache.cacheConfig.maxAge: number = 0;

    // 所有缓存占用的磁盘空间限制(单位: 字节); 0 表示不限制;
    // MCMediaCache.cacheConfig.maxDiskSize: number = 0;

    // 磁盘空间预警阈值(单位: 字节); 默认 1G;
    // MCMediaCache.cacheConfig.diskSpaceWarningThreshold: number;

    // 详细配置请查看 README.md
    MCMediaCache.setLogEnabled(BuildProfile.DEBUG); // 是否开启日志;
    MCMediaCache.setLogLevel(MCLogLevel.DEBUG); // 设置日志等级;
    MCMediaCache.setLogWhiteModules([MCLogModule.MCHttpConnectionHandler, MCLogModule.MCHttpResponse, MCLogModule.MCMediaContentLoader, MCLogModule.MCMediaDataFetcher]) // 允许打印哪些模块的日志;
    // MCMediaCache.setRequestHandler((request) => {
    //   request.setHeader('key', 'value');
    // });
    // MCMediaCache.setDataEncryptHandler(async (resUrl, dataOffset, data) => {
    //   // xxx
    // });
    MCMediaCache.prepare(getContext());
  }

  @State mX: number = 0;
  @State mY: number = 0;
  @State mPrevOffsetX: number = 0;
  @State mPrevOffsetY: number = 0;

  build() {
    Column() {
      Text("Test play")
        .id('测试播放')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => this.testPlay())

      Text(this.prefetchState)
        .id('测试预缓存')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => this.testPrefetch())

      Text(this.exportState)
        .id('测试导出到指定目录')
        .fontColor(0xFF1493)
        .fontSize(100)
        .fontWeight(FontWeight.Bold)
        .translate({ x: this.mX, y: this.mY})
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        // .onClick(() => this.testExport())
        .gesture(PanGesture().onActionStart(event => {
          this.mPrevOffsetX = event.offsetX;
          this.mPrevOffsetY = event.offsetY;
        }).onActionUpdate(event => {
          this.mX += event.offsetX - this.mPrevOffsetX;
          this.mY += event.offsetY - this.mPrevOffsetY;
          this.mPrevOffsetX = event.offsetX;
          this.mPrevOffsetY = event.offsetY;
        }).onActionEnd(event => {

        }).onActionCancel(() => {

        }))
    }
  }

  async testPlay() {
    // router.pushUrl({ url: 'pages/VideoPlayer' }).then(() => {
    //   console.info('Succeeded in jumping to the second page.')
    // }).catch((err: BusinessError) => {
    //   console.error(`Failed to jump to the second page. Code is ${err.code}, message is ${err.message}`)
    // })

    let url = 'https://consumer.huawei.com/content/dam/huawei-cbg-site/cn/mkt/pdp/phones/nova-flip/new/video/design-intro-popup.mp4';
    let proxyUrl = await MCMediaCache.proxy(url);

    router.pushUrl({ url: 'pages/VideoPlayer', params: { url: proxyUrl } }).then(() => {
      console.info('Succeeded in jumping to the second page.')
    }).catch((err: BusinessError) => {
      console.error(`Failed to jump to the second page. Code is ${err.code}, message is ${err.message}`)
    })
  }

  testPrefetch() {
    this.prefetchState = '开始预加载';
    const videoUrl: string = 'http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8';
    MCMediaCache.prefetch(videoUrl, {
      prefetchSegmentCount: 10,
      onProgress: (progress) => {
        this.prefetchState = progress.toFixed(2);
        console.log(`[prefech progress] ${progress}`);
      }
    }).then(() => {
      this.prefetchState = '预加载完成';
    }).catch((e: Error) => {
      console.log(`[prefech error] ${e.message}`);
      this.prefetchState = '预加载失败';
    });
  }

  async testExport() {
    this.exportState = '开始导出';

    // 视频播放地址
    const videoUrl = 'https://consumer.huawei.com/content/dam/huawei-cbg-site/cn/mkt/pdp/phones/nova-flip/new/video/design-intro-popup.mp4';

    const ctx = this.getUIContext().getHostContext()!;
    // 导出目录
    const targetDir = ctx.filesDir + '/my_exports/video1';

    // 开始导出
    MCMediaCache.exportToDirectory(videoUrl, targetDir, {
      conflictStrategy: MCCopyFileConflictStrategy.Overwrite,
      onProgress: (progress) => {
        this.exportState = progress.toFixed(2);
        console.log(`[export progress] ${progress}`);
      }
    }).then(() => {
      this.exportState = '导出完成';
    }).catch((e: Error) => {
      console.log(`[export error] ${e.message}`);
      this.exportState = '导出失败';
    });
  }
}