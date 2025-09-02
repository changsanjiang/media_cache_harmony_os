import { MCCopyFileConflictStrategy, MCMediaCache } from '../../Index';

/** 导出到指定目录 */
@ComponentV2
export struct ExportPage {
  private mLoading: boolean = true;
  private mError: string | null = null;
  private mProgress: number = 0;
  private mTargetDir: string = '/data/storage/el2/base/files/media_export';
  private mPlaybackUrl: string = '';

  async aboutToAppear(): Promise<void> {
    try {
      // 初始化 MCMediaCache;
      // 请在 app 启动后初始化一次即可;
      await MCMediaCache.prepare(this.getUIContext().getHostContext()!);

      // 需要导出的视频链接
      const resUrl = "https://example.com/video/test.mp4";

      // 1. 导出到本地目录
      await MCMediaCache.exportToDirectory(resUrl, this.mTargetDir, {
        conflictStrategy: MCCopyFileConflictStrategy.Overwrite,
        onProgress: (progress: number) => { // 导出进度回调
          this.mProgress = Math.floor(progress * 100);
          console.info(`Export progress: ${this.mProgress}%`);
        }
      });
      console.info(`导出完成 ✅ 目标目录: ${this.mTargetDir}`);

      // 2. 当需要时可代理该目录生成可播放地址
      this.mPlaybackUrl = await MCMediaCache.proxyDir(this.mTargetDir);
      console.info(`代理播放地址: ${this.mPlaybackUrl}`);
    }
    catch (err) {
      this.mError = `导出/代理失败: ${err}`;
      console.error(this.mError);
    }
    finally {
      this.mLoading = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      if (this.mLoading) {
        Text(`正在导出... ${this.mProgress}%`)
          .fontSize(16)
          .margin({ top: 20 })
      }
      else if (this.mError) {
        Text(this.mError)
          .fontColor(Color.Red)
          .fontSize(14)
      }
      else {
        Column({ space: 16 }) {
          Text("导出完成 ✅ 开始播放")
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.Green)

          Video({ src: this.mPlaybackUrl })
            .height('60%')
            .objectFit(ImageFit.Fill)
            .onError(() => {
              console.error("播放器发生错误 ⚠️");
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
