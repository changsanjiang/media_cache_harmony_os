import { MCRange } from '../utils/MCRange';

/// 选一个媒体进行代理
///
/// 例如: 以下变体流 二选一, 选 low 还是 high;
///
/// #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="audio-group"
/// https://example.com/low/index.m3u8
///
/// #EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2500000,RESOLUTION=1280x720,FRAME-RATE=60,CODECS="avc1.4d4028,mp4a.40.2",AUDIO="audio-group",SUBTITLES="subs-group"
/// https://example.com/high/index.m3u8
export type HLSVariantStreamSelectionHandler = (
  playlistOriginalUrl: string,
  playlistCurrentUrl: string,
  variantStreams: HLSDefines.VariantStreamItem[]
) => HLSDefines.VariantStreamItem;

/// AUDIO 二选一
/// #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en",URI="audio_eng.m3u8"
/// #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Spanish",LANGUAGE="es",URI="audio_spa.m3u8"
///
/// SUBTITLES 二选一
/// #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",URI="subs_eng.m3u8"
/// #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Spanish",LANGUAGE="es",URI="subs_spa.m3u8"
export type HLSRenditionSelectionHandler = (
  playlistOriginalUrl: string,
  playlistCurrentUrl: string,
  renditionGroup: HLSDefines.RenditionGroup,
  renditionType: HLSDefines.RenditionType
) => HLSDefines.RenditionItem;

/** https://datatracker.ietf.org/doc/html/rfc8216#section-4; */
export namespace HLSDefines {
  export enum ItemType {
    KEY, // #EXT-X-KEY
    INITIALIZATION, // #EXT-X-MAP
    SEGMENT, // #EXTINF
    VARIANT_STREAM, // #EXT-X-STREAM-INF
    IFRAME_STREAM, // #EXT-X-I-FRAME-STREAM-INF; ignored;
    RENDITION, // #EXT-X-MEDIA;
  }

  /// 因为需要代理请求, 所以我们关注更多的是  Playlist 中的这些URI;
  ///
  /// uri 可能未定义, 某些 Tag 会移除掉或无 URI 配置, 例如会移除 IFrameStreams; CLOSED-CAPTIONS 无 URI 通常嵌入在视频流中;
  export interface Item {
    readonly uri?: string;
    readonly itemType: ItemType;
    readonly contentRange: MCRange;
    readonly uriRange?: MCRange;
  }

  /// #EXT-X-KEY
  export interface KeyItem extends Item {
  }

  /// #EXT-X-MAP
  export interface InitializationItem extends Item {
    /// BYTERANGE or undefined; OPTIONAL: specifies byte range for initialization file;
    readonly byteRange?: MCRange;
  }

  /// #EXTINF
  export interface SegmentItem extends Item {
    readonly byteRange?: MCRange; // #EXT-X-BYTERANGE or undefined; OPTIONAL;
  }

  /// #EXT-X-STREAM-INF
  export interface VariantStreamItem extends Item {
    readonly bandwidth: number;               // REQUIRED: BANDWIDTH attribute
    readonly averageBandwidth: number;        // OPTIONAL: AVERAGE-BANDWIDTH attribute
    readonly codecs?: string;                 // OPTIONAL: CODECS attribute
    readonly resolution?: string;             // OPTIONAL: RESOLUTION attribute
    readonly frameRate?: string;              // OPTIONAL: FRAME-RATE attribute
    readonly audioGroupID?: string;           // OPTIONAL: AUDIO group ID
    readonly videoGroupID?: string;           // OPTIONAL: VIDEO group ID
    readonly subtitlesGroupID?: string;       // OPTIONAL: SUBTITLES group ID
    readonly closedCaptionsGroupID?: string;  // OPTIONAL: CLOSED-CAPTIONS group ID
  }

  /// #EXT-X-I-FRAME-STREAM-INF
  ///
  /// ignored;
  export interface IFrameStreamItem extends Item {
  }

  /// https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.4.1
  /// valid strings are AUDIO, VIDEO, SUBTITLES, and CLOSED-CAPTIONS.
  export enum RenditionType {
    AUDIO,
    VIDEO,
    SUBTITLES,
    CLOSED_CAPTIONS, // ignored; 通常嵌入在视频流中无需代理;
  }

  // #EXT-X-MEDIA
  /// https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.4.1
  export interface RenditionItem extends Item {
    readonly renditionType: RenditionType;
    readonly groupId: string;
    readonly name: string;
    readonly language?: string;
    readonly isDefault: boolean;
    readonly isAutoSelect: boolean;
  }

  export interface RenditionGroup {
    readonly groupId: string;
    readonly renditionType: RenditionType;
    readonly renditions: RenditionItem[];
  }

  export interface Playlist {
    readonly allItems?: Item[];
    readonly keys?: KeyItem[];
    readonly initializations?: InitializationItem[];
    readonly segments?: SegmentItem[];

    // In the proxy playlist, the content related to iframe streams will be removed,
    // and no proxy content will be generated for it.
    // readonly  iframeStreams?: IFrameStreamItem[];

    /// Represents the selected variant stream. If there are variant streams in the m3u8, only one can be selected.
    /// The selection is made through VariantStreamSelectionHandler.
    readonly variantStream?: VariantStreamItem;
    /// Represents the selected audio rendition. If there are audio renditions in the m3u8, only one can be selected.
    /// The selection is made through RenditionSelectionHandler.
    readonly audioRendition?: RenditionItem;
    /// Represents the selected video rendition. If there are video renditions in the m3u8, only one can be selected.
    /// The selection is made through RenditionSelectionHandler.
    readonly videoRendition?: RenditionItem;
    /// Represents the selected subtitles rendition. If there are subtitles renditions in the m3u8, only one can be selected.
    /// The selection is made through RenditionSelectionHandler.
    readonly subtitlesRendition?: RenditionItem;
    // only one can be selected;
    // readonly variantStreams?: RenditionItem[];
    // getRenditionGroupBy(groupId: string, renditionType: RenditionType): RenditionGroup | undefined;
  }

  interface Attribute {
    // readonly pair: string;

    /**
     * https://datatracker.ietf.org/doc/html/rfc8216#section-4.2
     An AttributeName is an unquoted string containing characters from the
     set [A..Z], [0..9] and '-'.  Therefore, AttributeNames contain only
     uppercase letters, not lowercase.  There MUST NOT be any whitespace
     between the AttributeName and the '=' character, nor between the '='
     character and the AttributeValue.
     * */
    readonly attrName: string;
    readonly attrValue: string;
    // readonly attrValue: string;
    readonly attrValueLocation: number;
  }

  /// AttributeName=AttributeValue
  /// `TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",URI="subs_eng.m3u8"`
  export function parseAttributes(rawStr: string): Attribute[] {
    const results: Attribute[] = [];
    const regex = /([A-Z0-9\-]+)=((?:"[^"]+")|(?:[^,]+))/g;
    while (true) {
      const match = regex.exec(rawStr);
      if ( !match ) break;
      results.push(parseAttribute(match))
    }
    return results;
  }

  function parseAttribute(match: RegExpExecArray): Attribute {
    const name = match[1];
    let value = match[2];
    let valueLocation = match.index + name.length + 1; // + '='.length;
    if ( value.startsWith(`"`) && value.endsWith(`"`) ) { // 处理双引号, 前后双引号不计入 value 的范围;
      value = value.slice(1, value.length - 1);
      valueLocation += 1;
    }
    return { attrName: name, attrValue: value, attrValueLocation: valueLocation };
  }

  /// https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.4.1
  /// valid strings are AUDIO, VIDEO, SUBTITLES, and CLOSED-CAPTIONS.
  export function parseRenditionType(rawStr: string): RenditionType {
    switch (rawStr) {
      case "AUDIO": return RenditionType.AUDIO;
      case "VIDEO": return RenditionType.VIDEO;
      case "SUBTITLES": return RenditionType.SUBTITLES;
      case "CLOSED-CAPTIONS": return RenditionType.CLOSED_CAPTIONS;
      default: throw new Error(`Unknown rendition type string: ${rawStr}`);
    }
  }

  /// valid strings are YES and NO;
  export function parseBoolean(rawStr: string): boolean {
    switch (rawStr) {
      case "YES": return true;
      case "NO": return false;
      default: throw new Error(`Unknown Boolean string: ${rawStr}`);
    }
  }

  /// #EXT-X-BYTERANGE:<n>[@<o>]
  export function parseByteRange(byteRange: string, prevEnd: number): MCRange {
    // 拆分 n (字节长度) 和 o (字节偏移量), 分隔符是 "@"
    const components = byteRange.split(`@`);
    // 解析 n;
    const length = parseInt(components[0], 10);
    // 如果有 o, 解析 o;
    // 如果没有 o, 使用前一个片段的末尾作为起点;
    const location = components[1] ? parseInt(components[1], 10) : prevEnd;
    return new MCRange(location, length);
  }
}