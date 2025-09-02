import { MCMediaCache } from '../../Index';

/** 代理播放示例 */
@ComponentV2
export struct ProxyPlayPage {
  private mProxyUrl: string = '';
  async aboutToAppear(): Promise<void> {
    // 初始化 MCMediaCache;
    // 请在 app 启动后初始化一次即可;
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    // 原始播放链接
    const resUrl = "https://example.com/video/test.mp4";
    console.info(`原始播放地址: ${resUrl}`);

    // 生成代理地址
    this.mProxyUrl = await MCMediaCache.proxy(resUrl);
    console.info(`代理播放地址: ${this.mProxyUrl}`);
  }

  build() {
    // 使用代理地址播放即可实现`边播放边缓存`
    Video({ src: this.mProxyUrl })
      .height('60%')
      .objectFit(ImageFit.Fill)
      .onError(() => {
        console.error(`AAAA: player on Error!`);
      })
  }
}