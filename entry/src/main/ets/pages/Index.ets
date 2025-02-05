import { MCLogLevel, MCLogModule, MCMediaCache } from "@sj/mediacache";
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import BuildProfile from "BuildProfile";

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';

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
    MCMediaCache.setLogWhiteModules([MCLogModule.MCHttpConnectionHandler, MCLogModule.MCHttpResponse]) // 允许打印哪些模块的日志;
    // MCMediaCache.setRequestHandler((request) => {
    //   request.setHeader('key', 'value');
    // });
    // MCMediaCache.setDataEncryptHandler(async (resUrl, dataOffset, data) => {
    //   // xxx
    // });
    MCMediaCache.prepare();
  }

  build() {
    Column() {
      Text("Test play")
        .id('Test play')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => this.testPlay())

      Text("Test prefetch")
        .id('Test prefetch')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => this.testPrefetch())
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
    const videoSrc: string = 'http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8';
    MCMediaCache.prefetch(videoSrc, {
      prefetchSegmentCount: 10,
      onProgress: (progress) => console.log(`[progress] ${progress}`)
    });
  }
}