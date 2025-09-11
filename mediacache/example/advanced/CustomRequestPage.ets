import { MCMediaCache } from '../../Index';

/** 设置自定义请求头 */
@ComponentV2
export struct CustomRequestPage {
  private mPlaybackUrl: string = '';

  async aboutToAppear(): Promise<void> {
    // 初始化 MCMediaCache;
    // 请在 app 启动后初始化一次即可;
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    // 设置自定义请求头; 可获取请求的 url 进行判断做一些参数配置;
    // 在 app 启动后配置一次即可;
    MCMediaCache.setRequestHandler((request) => {
      request.setHeader('Authorization', 'Bearer fake-token-123');
      request.setHeader('X-Custom-Client', 'HarmonyOS-Example');
      console.info(`Custom headers injected ✅`);
    });

    // 需要播放的视频链接
    const resUrl = "https://example.com/video/test.mp4";
    // 生成代理播放链接
    this.mPlaybackUrl = await MCMediaCache.proxy(resUrl);
  }

  build() {
    Video({ src: this.mPlaybackUrl })
      .height("60%")
      .objectFit(ImageFit.Fill)
  }
}
