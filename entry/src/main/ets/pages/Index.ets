import { MCLogLevel, MCLogModule, MCMediaCache, DashParser, XmlParser } from '@sj/mediacache';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import BuildProfile from 'BuildProfile';
import { MCCopyFileConflictStrategy } from '@sj/mediacache/src/main/ets/src/defines/MCCopyFileConflictStrategy';
import { trustedAppService } from '@kit.DeviceSecurityKit';

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State prefetchState: string = 'Test Prefetch';
  @State exportState: string = 'Test Export';

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

    this.testDash()
  }

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
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => this.testExport())

      Text('Test Dash')
        .id('测试Dash')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => this.testDash())
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

    // const videoUrl = 'http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8';
    // const ctx = this.getUIContext().getHostContext()!;
    // const targetDir = ctx.filesDir + '/my_exports/video2';

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

  async testDash() {
    const xmlText = `<?xml version="1.0" encoding="utf-8"?>
<MPD xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xmlns="urn:mpeg:dash:schema:mpd:2011"
	xmlns:xlink="http://www.w3.org/1999/xlink"
	xsi:schemaLocation="urn:mpeg:DASH:schema:MPD:2011 http://standards.iso.org/ittf/PubliclyAvailableStandards/MPEG-DASH_schema_files/DASH-MPD.xsd"
	profiles="urn:mpeg:dash:profile:isoff-live:2011"
	type="static"
	mediaPresentationDuration="PT9M21.7S"
	maxSegmentDuration="PT5.0S"
	minBufferTime="PT15.1S">
	<ProgramInformation>
	</ProgramInformation>
	<ServiceDescription id="0">
	</ServiceDescription>
	<Period id="0" start="PT0.0S">
		<AdaptationSet id="0" contentType="video" startWithSAP="1" segmentAlignment="true" bitstreamSwitching="true" frameRate="50/1" maxWidth="1920" maxHeight="1080" par="16:9" lang="und">
			<Representation id="0" mimeType="video/mp4" codecs="avc1.64002a" bandwidth="2224366" width="1920" height="1080" sar="1:1">
				<SegmentTemplate timescale="12800" initialization="init-stream$RepresentationID$.m4s" media="chunk-stream$RepresentationID$-$Number%05d$.m4s" startNumber="1">
					<SegmentTimeline>
						<S t="0" d="78592" />
						<S d="64000" r="23" />
						<S d="123392" />
						<S d="64000" r="13" />
						<S d="90624" />
						<S d="64000" />
						<S d="78592" />
						<S d="115968" />
						<S d="64000" r="10" />
						<S d="114944" />
						<S d="120576" />
						<S d="64000" r="26" />
						<S d="79360" />
						<S d="64000" r="5" />
						<S d="122880" />
						<S d="64000" r="5" />
						<S d="90624" />
						<S d="96512" />
						<S d="64000" r="3" />
						<S d="97024" />
						<S d="28672" />
					</SegmentTimeline>
				</SegmentTemplate>
			</Representation>
		</AdaptationSet>
		<AdaptationSet id="1" contentType="audio" startWithSAP="1" segmentAlignment="true" bitstreamSwitching="true" lang="und">
			<Representation id="1" mimeType="audio/mp4" codecs="mp4a.40.2" bandwidth="128000" audioSamplingRate="48000">
				<AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2" />
				<SegmentTemplate timescale="48000" initialization="init-stream$RepresentationID$.m4s" media="chunk-stream$RepresentationID$-$Number%05d$.m4s" startNumber="1">
					<SegmentTimeline>
						<S t="0" d="239616" />
						<S d="240640" r="110" />
						<S d="13312" />
					</SegmentTimeline>
				</SegmentTemplate>
			</Representation>
			<Representation id="2" mimeType="audio/mp4" codecs="mp4a.40.2" bandwidth="128000" audioSamplingRate="48000">
				<AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2" />
				<SegmentTemplate timescale="48000" initialization="init-stream$RepresentationID$.m4s" media="chunk-stream$RepresentationID$-$Number%05d$.m4s" startNumber="1">
					<SegmentTimeline>
						<S t="0" d="239616" />
						<S d="240640" r="110" />
						<S d="13312" />
					</SegmentTimeline>
				</SegmentTemplate>
			</Representation>
			<Representation id="3" mimeType="audio/mp4" codecs="mp4a.40.2" bandwidth="128000" audioSamplingRate="48000">
				<AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2" />
				<SegmentTemplate timescale="48000" initialization="init-stream$RepresentationID$.m4s" media="chunk-stream$RepresentationID$-$Number%05d$.m4s" startNumber="1">
					<SegmentTimeline>
						<S t="0" d="239616" />
						<S d="240640" r="110" />
						<S d="13312" />
					</SegmentTimeline>
				</SegmentTemplate>
			</Representation>
		</AdaptationSet>
	</Period>
</MPD>`;
    console.log(`AAAA: TestDash`)

    // const nodeTree = XmlParser.parseXmlToTree(xmlText)
    // console.log(`AAAA: ${nodeTree}`);

    try {
      const result = DashParser.proxy(
        xmlText,
        "assetId",
        "http://mpdOriginalUrl",
        "http://mpdCurrentUrl"
      );

      console.log(`AAAA: ${result}`);
    }
    catch (e) {
      console.log(`AAAA: e=${e}`);
    }

    // const mpd = DashUtils.parse(xmlText);
    // console.log(`AAAA: mpd=${JSON.stringify(mpd)}`)
    //
    // const urls = XmlParser.findElementRanges(xmlText, "BaseURL");
    // urls.forEach(range => {
    //   console.log(`AAAA: xml=${xmlText.substring(range.location, range.max)}`)
    // })
  }
}