import { webview } from '@kit.ArkWeb';
import { MCLogLevel, MCLogModule, MCMediaCache } from '@sj/mediacache';

@Entry
@Component
struct TestWebView {
  controller: webview.WebviewController = new webview.WebviewController();

  url: string = '';

  async aboutToAppear(): Promise<void> {
    await MCMediaCache.prepare(this.getUIContext().getHostContext()!);
    MCMediaCache.setLogEnabled(true);
    MCMediaCache.setLogLevel(MCLogLevel.DEBUG);

    const videoUrl =
      'https://consumer.huawei.com/content/dam/huawei-cbg-site/cn/mkt/pdp/phones/nova-flip/new/video/design-intro-popup.mp4';
    const proxyUrl = await MCMediaCache.proxy(videoUrl);
    console.log(`proxyUrl=${proxyUrl}`);

    this.url = `resource://rawfile/local.html?targetUrl=${encodeURIComponent(proxyUrl)}`;

    // const videoUrl = 'https://consumer.huawei.com/content/dam/huawei-cbg-site/cn/mkt/pdp/phones/nova-flip/new/video/design-intro-popup.mp4';
    // this.url = `resource://rawfile/local.html?targetUrl=${encodeURIComponent(videoUrl)}`;
    this.controller.loadUrl(this.url);

    console.log(`url=${this.url}`);
  }

  build() {
    Column() {
      Web({ src: this.url, controller: this.controller });
    }
  }
}