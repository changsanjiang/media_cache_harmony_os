import { MCMediaCache } from '../../Index';

/** 加解密处理 */
@ComponentV2
export struct EncryptDecryptPage {
  private mPlaybackUrl: string = '';

  async aboutToAppear(): Promise<void> {
    // 初始化 MCMediaCache;
    // 请在 app 启动后初始化一次即可;
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

    // 设置数据加密逻辑
    // 在 app 启动后配置一次即可;
    MCMediaCache.setDataEncryptHandler(async (url, offset, data) => {
      let view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = view[i] ^ 0xAA; // 简单异或加密
      }
      return data;
    });

    // 设置数据解密逻辑
    // 在 app 启动后配置一次即可;
    MCMediaCache.setDataDecryptHandler(async (url, offset, data) => {
      let view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = view[i] ^ 0xAA; // 解密（同样异或）
      }
      return data;
    });

    const resUrl = "https://example.com/video/test.mp4";
    this.mPlaybackUrl = await MCMediaCache.proxy(resUrl);
  }

  build() {
    Video({ src: this.mPlaybackUrl })
      .height("60%")
      .objectFit(ImageFit.Fill)
  }
}
