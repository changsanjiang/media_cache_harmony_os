import { MCRange } from "../../utils/MCRange";
import HLSDefines from "../../defines/HLSDefines";
import { MCProxyGenerator, MCUtils } from "../../../../../../Index";

namespace HLSParser {

  // 解析 playlist;
  export function parse(playlist: string, outputs: HLSDefines.Item[], shouldTrim: boolean = false): string {
    let trimmedPlaylist = "";
    let offset = 0; // content offset
    const ctx: Map<string, Object> = new Map();
    const lines = playlist.split(`\n`);
    lines.forEach((line) => {
      if ( shouldTrim && trimmedPlaylist.length !== 0 ) trimmedPlaylist += `\n`;
      const curLine = shouldTrim ? line.trim() : line; // 去除行首尾的空白字符; 每一行要么是一个标签(以 #EXT 开头), 要么是一个 URI

      // 跳过空行和注释
      const isTag = curLine.startsWith(TAG_PREFIX);
      const isComments = !isTag && curLine.startsWith(`#`);
      const isUri = !isTag && !isComments && curLine.length > 0;
      if      ( isTag ) handleTag(curLine, offset, outputs, ctx); // 这是一个标签行
      else if ( isUri ) handleURI(curLine, offset, ctx); // 这是一个 URI 行

      if ( shouldTrim && !isComments ) trimmedPlaylist += curLine;
      offset = (shouldTrim ? trimmedPlaylist.length : (offset + curLine.length)) + 1; // + "\n".length;
    });
    return shouldTrim ? trimmedPlaylist : playlist;
  }

  // 代理 playlist; throw if error;
  export function proxy(assetId: string, playlist: string, originalUrl: string, currentUrl: string, variantStreamSelectionHandler?: HLSDefines.VariantStreamSelectionHandler, renditionSelectionHandler?: HLSDefines.RenditionSelectionHandler): string {
    try {
      // let decoder = util.TextDecoder.create('utf-8');
      // let rawContent = decoder.decodeToString(new Uint8Array(playlist));
      const parsedItems: Item[] = [];
      let proxyPlaylist = parse(playlist, parsedItems, true);
      let variantStreams: HLSDefines.VariantStreamItem[] | undefined;
      let renditionGroups: Map<string, RenditionGroup> | undefined;
      parsedItems.forEach((item) => {
        switch (item.itemType) {
          case HLSDefines.ItemType.VARIANT_STREAM: {
            if ( !variantStreams ) variantStreams = [];
            variantStreams.push(item as HLSDefines.VariantStreamItem);
          }
            break;
          case HLSDefines.ItemType.RENDITION: {
            if ( !renditionGroups ) renditionGroups = new Map();
            const rendition = item as RenditionItem;
            const key = generateRenditionGroupKey(rendition.groupId, rendition.renditionType);
            let group = renditionGroups.get(key);
            if ( !group ) {
              group = new RenditionGroup(rendition.groupId, rendition.renditionType);
              renditionGroups.set(key, group);
            }
            group.renditions.push(rendition);
          }
            break;
        }
      });

      // selected variant stream
      let selectedVariantStream: HLSDefines.VariantStreamItem | undefined;
      // selected renditions
      let selectedAudioRendition: HLSDefines.RenditionItem | undefined;
      let selectedVideoRendition: HLSDefines.RenditionItem | undefined;
      let selectedSubtitlesRendition: HLSDefines.RenditionItem | undefined;

      if ( variantStreams && renditionGroups ) {
        selectedVariantStream = selectVariantStream(originalUrl, currentUrl, variantStreams, variantStreamSelectionHandler);

        const audioGroupID = selectedVariantStream.audioGroupID;
        const videoGroupID = selectedVariantStream.videoGroupID;
        const subtitlesGroupID = selectedVariantStream.subtitlesGroupID;

        if ( audioGroupID ) selectedAudioRendition = selectRendition(originalUrl, currentUrl, renditionGroups, audioGroupID, HLSDefines.RenditionType.AUDIO, renditionSelectionHandler);
        if ( videoGroupID ) selectedVideoRendition = selectRendition(originalUrl, currentUrl, renditionGroups, videoGroupID, HLSDefines.RenditionType.VIDEO, renditionSelectionHandler);
        if ( subtitlesGroupID ) selectedSubtitlesRendition = selectRendition(originalUrl, currentUrl, renditionGroups, subtitlesGroupID, HLSDefines.RenditionType.SUBTITLES, renditionSelectionHandler);
      }

      parsedItems.reverse().forEach((item) => {
        let shouldRemove = false;
        switch (item.itemType) {
          case HLSDefines.ItemType.VARIANT_STREAM:
            // remove unselected variant streams
            shouldRemove = item !== selectedVariantStream;
            break;
          case HLSDefines.ItemType.RENDITION:
            // remove unselected renditions
            shouldRemove = !(item === selectedAudioRendition || item === selectedVideoRendition || item === selectedSubtitlesRendition);
            break;
          case HLSDefines.ItemType.IFRAME_STREAM:
            // remove iframe streams
            shouldRemove = true;
            break;
        }

        // remove
        if ( shouldRemove ) {
          proxyPlaylist = MCUtils.replaceCharactersInRange(proxyPlaylist, [item.location.startPosition, item.location.length], "");
          return; // return;
        }

        // replace URI with proxy uri
        const uri = item.uri;
        if ( !uri ) return;

        const absoluteUrl = HLSDefines.getAbsoluteUrl(uri, currentUrl);
        const proxyUri = MCProxyGenerator.generateProxyURIForHLSItem(assetId, absoluteUrl, item.itemType);
        proxyPlaylist = MCUtils.replaceCharactersInRange(proxyPlaylist, [item.location.uriStartPosition, uri.length], proxyUri);
      });
      return proxyPlaylist;
    }
    catch (error) {
      throw error as Error;
    }
  }

  // https://tools.ietf.org/html/rfc8216

  const TAG_PREFIX = "#EXT";
  const EXT_X_KEY = "#EXT-X-KEY:";
  const EXT_X_MAP = "#EXT-X-MAP:";
  const EXTINF = "#EXTINF:";
  const EXT_X_BYTERANGE = "#EXT-X-BYTERANGE:";
  const EXT_X_MEDIA = "#EXT-X-MEDIA:";
  const EXT_X_STREAM_INF = "#EXT-X-STREAM-INF:";
  const EXT_X_I_FRAME_STREAM_INF = "EXT-X-I-FRAME-STREAM-INF:";

  const HLS_ATTR_URI = "URI";
  const HLS_ATTR_TYPE = "TYPE";
  const HLS_ATTR_GROUP_ID = "GROUP-ID";
  const HLS_ATTR_NAME = "NAME";
  const HLS_ATTR_LANGUAGE = "LANGUAGE";
  const HLS_ATTR_DEFAULT = "DEFAULT";
  const HLS_ATTR_AUTOSELECT = "AUTOSELECT";
  const HLS_ATTR_BANDWIDTH = "BANDWIDTH";
  const HLS_ATTR_CODECS = "CODECS";
  const HLS_ATTR_RESOLUTION = "RESOLUTION";
  const HLS_ATTR_VIDEO = "VIDEO";
  const HLS_ATTR_AUDIO = "AUDIO";
  const HLS_ATTR_SUBTITLES = "SUBTITLES";
  const HLS_ATTR_CLOSED_CAPTIONS = "CLOSED-CAPTIONS";
  const HLS_ATTR_AVERAGE_BANDWIDTH = "AVERAGE-BANDWIDTH";
  const HLS_ATTR_FRAME_RATE = "FRAME-RATE";
  const HLS_ATTR_BYTERANGE = "BYTERANGE";

  const HLS_CTX_LAST_ITEM = "HLS_CTX_LAST_ITEM";
  const HLS_CTX_LAST_BYTERANGE_END = "HLS_CTX_LAST_BYTERANGE_END";
  const HLS_CTX_LAST_INIT_END = "HLS_CTX_LAST_INIT_END";

  class Location implements HLSDefines.Location {
    startPosition: number = 0;
    length: number = 0;
    uriStartPosition: number = 0;

    constructor(startPosition: number) {
      this.startPosition = startPosition;
    }
  }

  class Item implements HLSDefines.Item {
    uri?: string | undefined;
    itemType: HLSDefines.ItemType;
    location: Location;

    constructor(itemType: HLSDefines.ItemType, startPosition: number) {
      this.itemType = itemType;
      this.location = new Location(startPosition);
    }
  }

  class KeyItem extends Item implements HLSDefines.KeyItem {
    constructor(startPosition: number) {
      super(HLSDefines.ItemType.KEY, startPosition);
    }
  }

  class InitializationItem extends Item implements HLSDefines.InitializationItem {
    constructor(startPosition: number, byteRange?: MCRange) {
      super(HLSDefines.ItemType.INITIALIZATION, startPosition);
      this.byteRange = byteRange;
    }

    byteRange?: MCRange;
  }

  class SegmentItem extends Item implements HLSDefines.SegmentItem {
    byteRange?: MCRange | undefined;

    constructor(startPosition: number) {
      super(HLSDefines.ItemType.SEGMENT, startPosition);
    }
  }

  class VariantStreamItem extends Item implements HLSDefines.VariantStreamItem {
    constructor(startPosition: number, bandwidth: number, averageBandwidth: number,
      codecs: string | undefined, resolution: string | undefined, frameRate: string | undefined,
      audioGroupID: string | undefined, videoGroupID: string | undefined, subtitlesGroupID: string | undefined,
      closedCaptionsGroupID: string | undefined) {
      super(HLSDefines.ItemType.VARIANT_STREAM, startPosition);
      this.bandwidth = bandwidth;
      this.averageBandwidth = averageBandwidth;
      this.codecs = codecs;
      this.resolution = resolution;
      this.frameRate = frameRate;
      this.audioGroupID = audioGroupID;
      this.videoGroupID = videoGroupID;
      this.subtitlesGroupID = subtitlesGroupID;
      this.closedCaptionsGroupID = closedCaptionsGroupID;
    }

    bandwidth: number;
    averageBandwidth: number;
    codecs?: string | undefined;
    resolution?: string | undefined;
    frameRate?: string | undefined;
    audioGroupID?: string | undefined;
    videoGroupID?: string | undefined;
    subtitlesGroupID?: string | undefined;
    closedCaptionsGroupID?: string | undefined;
  }

  class IFrameStreamItem extends Item implements HLSDefines.IFrameStreamItem {
    constructor(startPosition: number) {
      super(HLSDefines.ItemType.IFRAME_STREAM, startPosition);
    }
  }

  class RenditionItem extends Item implements HLSDefines.RenditionItem {
    constructor(startPosition: number, renditionType: HLSDefines.RenditionType,
      groupId: string, name: string, language: string | undefined, isDefault: boolean, isAutoSelect: boolean) {
      super(HLSDefines.ItemType.RENDITION, startPosition);
      this.renditionType = renditionType;
      this.groupId = groupId;
      this.name = name;
      this.language = language;
      this.isDefault = isDefault;
      this.isAutoSelect = isAutoSelect;
    }

    renditionType: HLSDefines.RenditionType;
    groupId: string;
    name: string;
    language?: string | undefined;
    isDefault: boolean;
    isAutoSelect: boolean;
  }

  class RenditionGroup implements HLSDefines.RenditionGroup {
    constructor(groupId: string, renditionType: HLSDefines.RenditionType) {
      this.groupId = groupId;
      this.renditionType = renditionType;
    }

    groupId: string;
    renditionType: HLSDefines.RenditionType;
    renditions: HLSDefines.RenditionItem[] = [];
  }

  function handleTag(tagLine: string, offset: number, outputs: Item[], ctx: Map<string, Object>) {
    /// #EXTINF:8.766667,
    /// #EXT-X-BYTERANGE:9194528@9662832
    /// segment.ts
    if ( tagLine.startsWith(EXTINF) ) {
      const segment = new SegmentItem(offset);
      outputs.push(segment);
      ctx.set(HLS_CTX_LAST_ITEM, segment);
    }
    /// #EXTINF:8.766667,
    /// #EXT-X-BYTERANGE:9194528@9662832
    /// segment.ts
    else if ( tagLine.startsWith(EXT_X_BYTERANGE) ) {
      const segment = ctx.get(HLS_CTX_LAST_ITEM) as SegmentItem;
      const byteRange = tagLine.slice(EXT_X_BYTERANGE.length);
      const prevEnd = (ctx.get(HLS_CTX_LAST_BYTERANGE_END) as number | undefined) ?? 0;
      const range = HLSDefines.parseByteRange(byteRange, prevEnd);
      segment.byteRange = range;
      ctx.set(HLS_CTX_LAST_BYTERANGE_END, range.max);
    }
    /// #EXT-X-KEY: https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.4
    ///
    /// #EXT-X-KEY:METHOD=NONE 这种情况下, 不需要 URI 和 IV, 表示后续的媒体段不加密;
    /// #EXT-X-KEY:METHOD=AES-128,URI="https://example.com/key",IV=0x1a2b3c4d5e6f7g8h9i0jklmnopqrst
    /// #EXT-X-KEY:METHOD=AES-128,URI="https://example.com/key"
    /// #EXT-X-KEY:METHOD=SAMPLE-AES,URI="https://example.com/key",KEYFORMAT="com.apple.streamingkeydelivery",KEYFORMATVERSIONS="1"
    /// #EXT-X-KEY:METHOD=SAMPLE-AES,URI="https://drm.example.com/widevine-key",KEYFORMAT="com.widevine.alpha",KEYFORMATVERSIONS="1/2"
    else if ( tagLine.startsWith(EXT_X_KEY) ) {
      const attrsRawStr = tagLine.slice(EXT_X_KEY.length);
      const attrs = HLSDefines.parseAttributes(attrsRawStr);
      const uriAttr = attrs.find((attr) => attr.attrName === HLS_ATTR_URI);
      if ( uriAttr ) {
        const uri = attrsRawStr.slice(uriAttr.attrValueRange.location, uriAttr.attrValueRange.max);
        const uriStartPosition = offset + EXT_X_KEY.length + uriAttr.attrValueRange.location;
        const key = new KeyItem(offset);
        key.uri = uri;
        key.location.uriStartPosition = uriStartPosition;
        key.location.length = tagLine.length;
        outputs.push(key);
      }
    }
    /// #EXT-X-MAP: https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.5
    ///
    /// #EXT-X-MAP:URI="init.mp4",BYTERANGE="1000@2000"
    else if ( tagLine.startsWith(EXT_X_MAP) ) {
      const attrsRawStr = tagLine.slice(EXT_X_MAP.length);
      const attrs = HLSDefines.parseAttributes(attrsRawStr);

      const uriAttr = attrs.find((attr) => attr.attrName === HLS_ATTR_URI)!;
      const uri = attrsRawStr.slice(uriAttr.attrValueRange.location, uriAttr.attrValueRange.max);
      const uriStartPosition = offset + EXT_X_MAP.length + uriAttr.attrValueRange.location;

      const init = new InitializationItem(offset);
      init.uri = uri;
      init.location.uriStartPosition = uriStartPosition;

      const byteRangeAttr = uriAttr ? attrs.find((attr) => attr.attrName === HLS_ATTR_BYTERANGE) : undefined;
      if ( byteRangeAttr ) {
        const byteRange = attrsRawStr.slice(byteRangeAttr.attrValueRange.location, byteRangeAttr.attrValueRange.max);
        const prevEnd = (ctx.get(HLS_CTX_LAST_INIT_END) as number | undefined) ?? 0;
        const range = HLSDefines.parseByteRange(byteRange, prevEnd);
        init.byteRange = range;
        ctx.set(HLS_CTX_LAST_INIT_END, range.max);
      }

      init.location.startPosition = offset;
      init.location.length = tagLine.length;
      outputs.push(init);
    }
    /// #EXT-X-MEDIA: https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.4.1
    ///
    /// #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en",URI="audio_eng.m3u8"
    /// #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Spanish",LANGUAGE="es",URI="audio_spa.m3u8"
    ///
    /// #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",URI="subs_eng.m3u8"
    /// #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Spanish",LANGUAGE="es",URI="subs_spa.m3u8"
    else if ( tagLine.startsWith(EXT_X_MEDIA) ) {
      const attrsRawStr = tagLine.slice(EXT_X_MEDIA.length);
      const attrs = HLSDefines.parseAttributes(attrsRawStr);

      let renditionType: HLSDefines.RenditionType | undefined;
      let groupId: string | undefined;
      let name: string | undefined;
      let language: string | undefined;
      let isDefault = false;
      let isAutoSelect = false;
      let uri: string | undefined;
      let uriStartPosition = 0;

      attrs.forEach((attr) => {
        const attrValueRange = attr.attrValueRange;
        const attrValue = attrsRawStr.slice(attrValueRange.location, attrValueRange.max);
        switch (attr.attrName) {
          case HLS_ATTR_TYPE:
            renditionType = HLSDefines.parseRenditionType(attrValue);
            break;
          case HLS_ATTR_GROUP_ID:
            groupId = attrValue;
            break;
          case HLS_ATTR_NAME:
            name = attrValue;
            break;
          case HLS_ATTR_LANGUAGE:
            language = attrValue;
            break;
          case HLS_ATTR_DEFAULT:
            isDefault = HLSDefines.parseBoolean(attrValue);
            break;
          case HLS_ATTR_AUTOSELECT:
            isAutoSelect = HLSDefines.parseBoolean(attrValue);
            break;
          case HLS_ATTR_URI: {
            uri = attrValue;
            uriStartPosition = offset + EXT_X_MEDIA.length + attrValueRange.location;
          }
            break;
        }
      });

      const rendition = new RenditionItem(offset, renditionType!, groupId!, name!, language, isDefault, isAutoSelect);
      if ( uri ) {
        rendition.uri = uri;
        rendition.location.uriStartPosition = uriStartPosition;
      }
      rendition.location.length = tagLine.length;
      outputs.push(rendition);
    }
    /// #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="audio-group"
    /// https://example.com/low/index.m3u8
    ///
    /// #EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2500000,RESOLUTION=1280x720,FRAME-RATE=60,CODECS="avc1.4d4028,mp4a.40.2",AUDIO="audio-group",SUBTITLES="subs-group"
    /// https://example.com/high/index.m3u8
    else if ( tagLine.startsWith(EXT_X_STREAM_INF) ) {
      const attrsRawStr = tagLine.slice(EXT_X_STREAM_INF.length);
      const attrs = HLSDefines.parseAttributes(attrsRawStr);

      let bandwidth: number = 0;               // REQUIRED: BANDWIDTH attribute
      let averageBandwidth: number = 0;        // OPTIONAL: AVERAGE-BANDWIDTH attribute
      let codecs: string | undefined;                 // OPTIONAL: CODECS attribute
      let resolution: string | undefined;             // OPTIONAL: RESOLUTION attribute
      let frameRate: string | undefined;              // OPTIONAL: FRAME-RATE attribute
      let audioGroupID: string | undefined;           // OPTIONAL: AUDIO group ID
      let videoGroupID: string | undefined;           // OPTIONAL: VIDEO group ID
      let subtitlesGroupID: string | undefined;       // OPTIONAL: SUBTITLES group ID
      let closedCaptionsGroupID: string | undefined;  // OPTIONAL: CLOSED-CAPTIONS group ID

      attrs.forEach((attr) => {
        const attrValueRange = attr.attrValueRange;
        const attrValue = attrsRawStr.slice(attrValueRange.location, attrValueRange.max);
        switch (attr.attrName) {
          case HLS_ATTR_BANDWIDTH:
            bandwidth = parseInt(attrValue, 10);
            break;
          case HLS_ATTR_AVERAGE_BANDWIDTH:
            averageBandwidth = parseInt(attrValue, 10);;
            break;
          case HLS_ATTR_CODECS:
            codecs = attrValue;
            break;
          case HLS_ATTR_RESOLUTION:
            resolution = attrValue;
            break;
          case HLS_ATTR_FRAME_RATE:
            frameRate = attrValue;
            break;
          case HLS_ATTR_AUDIO:
            audioGroupID = attrValue;
            break;
          case HLS_ATTR_VIDEO:
            videoGroupID = attrValue;
            break;
          case HLS_ATTR_SUBTITLES:
            subtitlesGroupID = attrValue;
            break;
          case HLS_ATTR_CLOSED_CAPTIONS:
            closedCaptionsGroupID = attrValue;
            break;
        }
      });

      const variantStream = new VariantStreamItem(offset, bandwidth, averageBandwidth, codecs, resolution, frameRate, audioGroupID, videoGroupID, subtitlesGroupID, closedCaptionsGroupID);
      outputs.push(variantStream);
      ctx.set(HLS_CTX_LAST_ITEM, variantStream);
    }
    /// #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=86000,URI="iframe-stream-1.m3u8"
    /// #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=150000,RESOLUTION=1920x1080,CODECS="avc1.4d001f",URI="iframe-stream-2.m3u8"
    /// #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=250000,RESOLUTION=1280x720,CODECS="avc1.42c01e",VIDEO="video-group-1",URI="iframe-stream-3.m3u8"
    /// #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=500000,RESOLUTION=854x480,CODECS="avc1.64001f",PROGRAM-ID=1,URI="iframe-stream-4.m3u8"
    /// #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=3840x2160,CODECS="hev1.1.6.L120.90",URI="iframe-stream-5.m3u8"
    else if ( tagLine.startsWith(EXT_X_I_FRAME_STREAM_INF) ) {
      // const attrsRawStr = tagLine.slice(EXT_X_I_FRAME_STREAM_INF.length);
      // const attrs = HLSDefines.parseAttributes(attrsRawStr);
      //
      // const uriAttr = attrs.find((attr) => attr.attrName === HLS_ATTR_URI)!;
      // const uri = attrsRawStr.slice(uriAttr.attrValueRange.location, uriAttr.attrValueRange.max);
      // const uriStartPosition = offset + EXT_X_I_FRAME_STREAM_INF.length + uriAttr.attrValueRange.location;

      // 这里不解析 iframe 的 uri, 在生成代理内容时将会被移除;
      const iframeStream = new IFrameStreamItem(offset);
      // iframeStream.uri = uri;
      // iframeStream.positions.uriStartPosition = uriStartPosition;
      iframeStream.location.length = tagLine.length;
      outputs.push(iframeStream);
    }
  }

  function handleURI(uri: string, offset: number, ctx: Map<string, Object>) {
    /// #EXTINF:8.766667,
    /// #EXT-X-BYTERANGE:9194528@9662832
    /// segment.ts
    ///
    ///
    /// #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="audio-group"
    /// https://example.com/low/index.m3u8
    ///
    const item = ctx.get(HLS_CTX_LAST_ITEM) as Item | undefined;
    if ( item && !item.uri ) {
      item.uri = uri;
      item.location.uriStartPosition = offset;
      item.location.length = offset + uri.length - item.location.startPosition;
      ctx.delete(HLS_CTX_LAST_ITEM);
    }
  }

  function selectVariantStream(originalUrl: string, currentUrl: string, streams: HLSDefines.VariantStreamItem[], variantStreamSelectionHandler?: HLSDefines.VariantStreamSelectionHandler): HLSDefines.VariantStreamItem {
    if ( variantStreamSelectionHandler ) {
      const stream = variantStreamSelectionHandler(originalUrl, currentUrl, streams);
      if ( stream ) return stream;
    }
    // Default: select the middle stream if no handler or valid selection.
    return streams[Math.floor((streams.length / 2))];
  }

  function generateRenditionGroupKey(groupId: string, renditionType: HLSDefines.RenditionType): string {
    return `${groupId}_${renditionType}`;
  }

  function selectRendition(originalUrl: string, currentUrl: string, groups: Map<string, HLSDefines.RenditionGroup>, groupId: string, renditionType: HLSDefines.RenditionType, renditionSelectionHandler?: HLSDefines.RenditionSelectionHandler): HLSDefines.RenditionItem {
    const key = generateRenditionGroupKey(groupId, renditionType);
    const group = groups.get(key);
    if ( !group ) {
      throw new Error(`Rendition group for ID "${groupId}" and type "${renditionType}" not found.`);
    }

    const renditions = group.renditions;
    if ( renditions.length > 1 ) {
      if ( renditionSelectionHandler ) {
        const rendition = renditionSelectionHandler(originalUrl, currentUrl, group, renditionType);
        if ( rendition ) return rendition;
      }
    }

    // Select default rendition if available; otherwise, fallback to the first rendition.
    return renditions.find((rendition) => rendition.isDefault) ?? renditions[0];
  }
}

export default HLSParser;