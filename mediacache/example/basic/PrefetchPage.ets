import { MCMediaCache } from '../../Index';

@ComponentV2
export struct PrefetchPage {
  private mLoading: boolean = true;
  private mError: string | null = null;
  private mProgress: number = 0;

  async aboutToAppear(): Promise<void> {
    try {
      // 初始化 MCMediaCache;
      // 请在 app 启动后初始化一次即可;
      await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

      // 需要预缓存的视频链接
      const resUrl = "https://example.com/video/test.mp4";

      // 开始预缓存
      await MCMediaCache.prefetch(resUrl, {
        prefetchSize: 5 * 1024 * 1024, // 预缓存 5MB
        onProgress: (progress: number) => { // 预缓存进度回调
          this.mProgress = Math.floor(progress * 100);
          console.info(`Prefetch progress: ${this.mProgress}%`);
        }
      });
      console.info("预缓存完成 ✅");
    }
    catch (err) {
      this.mError = `预缓存失败: ${err}`;
      console.error(this.mError);
    }
    finally {
      this.mLoading = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      if (this.mLoading) {
        Text(`正在预缓存... ${this.mProgress}%`)
          .fontSize(16)
          .margin({ top: 20 })
      }
      else if (this.mError) {
        Text(this.mError)
          .fontColor(Color.Red)
          .fontSize(14)
      }
      else {
        Text("预缓存完成 ✅")
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.Green)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}