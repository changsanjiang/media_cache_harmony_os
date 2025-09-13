
/** Dash adaptationSet 选择器;
 *
 *  对于多语言、多字幕轨道, 必须做出选择, 只能选择一个进行缓存;
 *
 * 一个复杂的电影流媒体可能包含如下结构：
 * - AdaptationSet 1: 视频 (包含5个不同码率的版本)
 * - AdaptationSet 2: 音频 - 中文 (包含2个不同码率的版本)
 * - AdaptationSet 3: 音频 - 英语 (包含2个不同码率的版本)
 * - AdaptationSet 5: 字幕 - 中文
 * - AdaptationSet 6: 字幕 - 英语
 *
 * <MPD>
 *  <Period>
 *    <AdaptationSet contentType="video" mimeType="video/mp4" ...>
 *      <Representation id="video_360p" bandwidth="500000" ... />
 *      <Representation id="video_720p" bandwidth="2000000" ... />
 *      <Representation id="video_1080p" bandwidth="5000000" ... />
 *    </AdaptationSet>
 *
 *    <AdaptationSet contentType="audio" lang="zh" mimeType="audio/mp4" ...>
 *      <Representation id="audio_zh_128k" bandwidth="128000" ... />
 *    </AdaptationSet>
 *
 *    <AdaptationSet contentType="audio" lang="en" mimeType="audio/mp4" ...>
 *      <Representation id="audio_eng_128k" bandwidth="128000" ... />
 *    </AdaptationSet>
 *
 *    <AdaptationSet contentType="text" lang="zh" mimeType="application/ttml+xml" ...>
 *      <Representation id="sub_zh" ... />
 *    </AdaptationSet>
 *
 *    <AdaptationSet contentType="text" lang="en" mimeType="application/ttml+xml" ...>
 *      <Representation id="sub_en" ... />
 *    </AdaptationSet>
 *  </Period>
 * </MPD>
 * */
export type DashAdaptationSetSelectionHandler = (
  mpdOriginalUrl: string,
  mpdCurrentUrl: string,
  contentType: string, // audio、 text(subtitles)
  adaptationSets: readonly DashElement.AdaptationSet[], // audios、texts(subtitles)
) => DashElement.AdaptationSet;

/** Dash representation 选择器;
 *
 * 对于多码率流, 必须做出选择, 选出一个需要缓存的流;
 *
 * <MPD>
 *  <Period>
 *    <AdaptationSet contentType="video" mimeType="video/mp4" ...>
 *      <Representation id="video_360p" bandwidth="500000" ... />
 *      <Representation id="video_720p" bandwidth="2000000" ... />
 *      <Representation id="video_1080p" bandwidth="5000000" ... />
 *    </AdaptationSet>
 *  </Period>
 * </MPD>
 * */
export type DashRepresentationSelectionHandler = (
  mpdOriginalUrl: string,
  mpdCurrentUrl: string,
  adaptationSet: DashElement.AdaptationSet,
  representations: readonly DashElement.Representation[],
) => DashElement.Representation;

/** XML 节点; */
export interface DashXmlNode {
  readonly tagName: string;
  readonly attributes?: Map<string, string>;
  readonly children: DashXmlNode[];
  readonly innerText?: string; // trimmed

  /** <tag ...> 的结束位置（相对节点自身起始位置） */
  readonly startTagEndIndex: number;
  /** innerText 起点（相对节点自身起始位置） */
  readonly innerTextStartIndex: number;
  /** 节点总长度（从 <tag ...> 到 </tag> 包含的总长度） */
  readonly length: number;
}

/** Dash 对象;
 *
 * https://standards.iso.org/ittf/PubliclyAvailableStandards/MPEG-DASH_schema_files/DASH-MPD.xsd
 * */
export namespace DashElement {
  // 因为目的是要代理请求, 所以在建立模型时不会对所有属性建模, 仅选择可能需要的属性

  // `minOccurs="0", maxOccurs="1"` 定义基数（cardinality）为 0 或 1, 代表该子元素最多只能定义一个
  // `minOccurs="0" maxOccurs="unbounded"` 代表该子元素可以定义多个
  // `minOccurs="0"` 未定义maxOccurs时默认值是1, 最多只能出现一次

  export interface Element {
    readonly node: DashXmlNode;
  }

  /** MPD 根对象
   <!--  MPD: main element  -->
   <xs:element name="MPD" type="MPDtype"/>
   <!--  MPD Type  -->
   <xs:complexType name="MPDtype">
   <xs:sequence>
   <xs:element name="ProgramInformation" type="ProgramInformationType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="Location" type="xs:anyURI" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="Period" type="PeriodType" maxOccurs="unbounded"/>
   <xs:element name="Metrics" type="MetricsType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="EssentialProperty" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="SupplementalProperty" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="UTCTiming" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:any namespace="##other" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence>
   <xs:attribute name="id" type="xs:string"/>
   <xs:attribute name="profiles" type="xs:string" use="required"/>
   <xs:attribute name="type" type="PresentationType" default="static"/>
   <xs:attribute name="availabilityStartTime" type="xs:dateTime"/>
   <xs:attribute name="availabilityEndTime" type="xs:dateTime"/>
   <xs:attribute name="publishTime" type="xs:dateTime"/>
   <xs:attribute name="mediaPresentationDuration" type="xs:duration"/>
   <xs:attribute name="minimumUpdatePeriod" type="xs:duration"/>
   <xs:attribute name="minBufferTime" type="xs:duration" use="required"/>
   <xs:attribute name="timeShiftBufferDepth" type="xs:duration"/>
   <xs:attribute name="suggestedPresentationDelay" type="xs:duration"/>
   <xs:attribute name="maxSegmentDuration" type="xs:duration"/>
   <xs:attribute name="maxSubsegmentDuration" type="xs:duration"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   * */
  export interface MPD extends Element {
    readonly eBaseURLs?: readonly BaseURL[];       // <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
    readonly ePeriods?: readonly Period[];         // <xs:element name="Period" type="PeriodType" maxOccurs="unbounded"/>
    // readonly aType: PresentationType;            // <xs:attribute name="type" type="PresentationType" default="static"/>
  }

  /** 一个 Period，DASH 流的时间分区
   <!--  Period  -->
   <xs:complexType name="PeriodType">
   <xs:sequence>
   <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="SegmentBase" type="SegmentBaseType" minOccurs="0"/>
   <xs:element name="SegmentList" type="SegmentListType" minOccurs="0"/>
   <xs:element name="SegmentTemplate" type="SegmentTemplateType" minOccurs="0"/>
   <xs:element name="AssetIdentifier" type="DescriptorType" minOccurs="0"/>
   <xs:element name="EventStream" type="EventStreamType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="AdaptationSet" type="AdaptationSetType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="Subset" type="SubsetType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="SupplementalProperty" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:any namespace="##other" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence>
   <xs:attribute ref="xlink:href"/>
   <xs:attribute ref="xlink:actuate" default="onRequest"/>
   <xs:attribute name="id" type="xs:string"/>
   <xs:attribute name="start" type="xs:duration"/>
   <xs:attribute name="duration" type="xs:duration"/>
   <xs:attribute name="bitstreamSwitching" type="xs:boolean" default="false"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   * */
  export interface Period extends Element {
    readonly eBaseURLs?: readonly BaseURL[]                   // <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
    // 暂不处理继承
    // eSegmentBase?: SegmentBaseElement              // <xs:element name="SegmentBase" type="SegmentBaseType" minOccurs="0"/>
    // eSegmentList?: SegmentListElement            // <xs:element name="SegmentList" type="SegmentListType" minOccurs="0"/>
    // eSegmentTemplate?: SegmentTemplateElement      // <xs:element name="SegmentTemplate" type="SegmentTemplateType" minOccurs="0"/>
    readonly eAdaptationSets?: readonly AdaptationSet[]       // <xs:element name="AdaptationSet" type="AdaptationSetType" minOccurs="0" maxOccurs="unbounded"/>
    // aId?: string                                 // <xs:attribute name="id" type="xs:string"/>
  }

  /**
   <!--  Representation base (common attributes and elements)  -->
   <xs:complexType name="RepresentationBaseType">
   <xs:sequence>
   <xs:element name="FramePacking" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="AudioChannelConfiguration" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="ContentProtection" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="EssentialProperty" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="SupplementalProperty" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="InbandEventStream" type="EventStreamType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:any namespace="##other" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence>
   <xs:attribute name="profiles" type="xs:string"/>
   <xs:attribute name="width" type="xs:unsignedInt"/>
   <xs:attribute name="height" type="xs:unsignedInt"/>
   <xs:attribute name="sar" type="RatioType"/>
   <xs:attribute name="frameRate" type="FrameRateType"/>
   <xs:attribute name="audioSamplingRate" type="xs:string"/>
   <xs:attribute name="mimeType" type="xs:string"/>
   <xs:attribute name="segmentProfiles" type="xs:string"/>
   <xs:attribute name="codecs" type="xs:string"/>
   <xs:attribute name="maximumSAPPeriod" type="xs:double"/>
   <xs:attribute name="startWithSAP" type="SAPType"/>
   <xs:attribute name="maxPlayoutRate" type="xs:double"/>
   <xs:attribute name="codingDependency" type="xs:boolean"/>
   <xs:attribute name="scanType" type="VideoScanType"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   * */
  export interface RepresentationBase {
    // readonly aWidth?: number                   // <xs:attribute name="width" type="xs:unsignedInt"/>
    // readonly aHeight?: number                  // <xs:attribute name="height" type="xs:unsignedInt"/>
    // readonly aFrameRate?: FrameRateType        // <xs:attribute name="frameRate" type="FrameRateType"/>
    // readonly aAudioSamplingRate?: string       // <xs:attribute name="audioSamplingRate" type="xs:string"/>
    // readonly aMimeType?: string                // <xs:attribute name="mimeType" type="xs:string"/>
    // readonly aSegmentProfiles?: string         // <xs:attribute name="segmentProfiles" type="xs:string"/>
    // readonly aCodecs?: string                  // <xs:attribute name="codecs" type="xs:string"/>
  }

  /** 一个 AdaptationSet，通常是一组相同类型的轨道（视频、音频、字幕）
   <!--  Adaptation Set  -->
   <xs:complexType name="AdaptationSetType">
   <xs:complexContent>
   <xs:extension base="RepresentationBaseType">
   <xs:sequence>
   <xs:element name="Accessibility" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="Role" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="Rating" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="Viewpoint" type="DescriptorType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="ContentComponent" type="ContentComponentType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="SegmentBase" type="SegmentBaseType" minOccurs="0"/>
   <xs:element name="SegmentList" type="SegmentListType" minOccurs="0"/>
   <xs:element name="SegmentTemplate" type="SegmentTemplateType" minOccurs="0"/>
   <xs:element name="Representation" type="RepresentationType" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence>
   <xs:attribute ref="xlink:href"/>
   <xs:attribute ref="xlink:actuate" default="onRequest"/>
   <xs:attribute name="id" type="xs:unsignedInt"/>
   <xs:attribute name="group" type="xs:unsignedInt"/>
   <xs:attribute name="lang" type="xs:language"/>
   <xs:attribute name="contentType" type="xs:string"/>
   <xs:attribute name="par" type="RatioType"/>
   <xs:attribute name="minBandwidth" type="xs:unsignedInt"/>
   <xs:attribute name="maxBandwidth" type="xs:unsignedInt"/>
   <xs:attribute name="minWidth" type="xs:unsignedInt"/>
   <xs:attribute name="maxWidth" type="xs:unsignedInt"/>
   <xs:attribute name="minHeight" type="xs:unsignedInt"/>
   <xs:attribute name="maxHeight" type="xs:unsignedInt"/>
   <xs:attribute name="minFrameRate" type="FrameRateType"/>
   <xs:attribute name="maxFrameRate" type="FrameRateType"/>
   <xs:attribute name="segmentAlignment" type="ConditionalUintType" default="false"/>
   <xs:attribute name="subsegmentAlignment" type="ConditionalUintType" default="false"/>
   <xs:attribute name="subsegmentStartsWithSAP" type="SAPType" default="0"/>
   <xs:attribute name="bitstreamSwitching" type="xs:boolean"/>
   </xs:extension>
   </xs:complexContent>
   </xs:complexType>
   * */
  // export interface AdaptationSetElement extends RepresentationBaseType {
  export interface AdaptationSet extends Element {
    readonly eBaseURLs?: readonly BaseURL[]                     // <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
    // 暂不处理继承
    // SegmentBase:                              // <xs:element name="SegmentBase" type="SegmentBaseType" minOccurs="0"/>
    // SegmentList:                              // <xs:element name="SegmentList" type="SegmentListType" minOccurs="0"/>
    // SegmentTemplate:                          // <xs:element name="SegmentTemplate" type="SegmentTemplateType" minOccurs="0"/>
    readonly eRepresentations?: readonly Representation[]       // <xs:element name="Representation" type="RepresentationType" minOccurs="0" maxOccurs="unbounded"/>
    // aId?: number                                  // <xs:attribute name="id" type="xs:unsignedInt"/>
    // aGroup?: number                               // <xs:attribute name="group" type="xs:unsignedInt"/>
    readonly aLang?: string                                // <xs:attribute name="lang" type="xs:language"/>
    readonly aContentType?: string                         // <xs:attribute name="contentType" type="xs:string"/>
    // aPar?: RatioType                              // <xs:attribute name="par" type="RatioType"/>
    // aMinBandwidth?: number                        // <xs:attribute name="minBandwidth" type="xs:unsignedInt"/>
    // aMaxBandwidth?: number                        // <xs:attribute name="maxBandwidth" type="xs:unsignedInt"/>
    // aMinWidth?: number                            // <xs:attribute name="minWidth" type="xs:unsignedInt"/>
    // aMaxWidth?: number                            // <xs:attribute name="maxWidth" type="xs:unsignedInt"/>
    // aMinHeight?: number                           // <xs:attribute name="minHeight" type="xs:unsignedInt"/>
    // aMaxHeight?: number                           // <xs:attribute name="maxHeight" type="xs:unsignedInt"/>
    // aMinFrameRate?: FrameRateType                 // <xs:attribute name="minFrameRate" type="FrameRateType"/>
    // aMaxFrameRate?: FrameRateType                 // <xs:attribute name="maxFrameRate" type="FrameRateType"/>
    // bitstreamSwitching: boolean // 只能选择一个Representation
  }

  /** 表示一个媒体表示 (Representation)
   <!--  Representation  -->
   <xs:complexType name="RepresentationType">
   <xs:complexContent>
   <xs:extension base="RepresentationBaseType">
   <xs:sequence>
   <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="SubRepresentation" type="SubRepresentationType" minOccurs="0" maxOccurs="unbounded"/>
   <xs:element name="SegmentBase" type="SegmentBaseType" minOccurs="0"/>
   <xs:element name="SegmentList" type="SegmentListType" minOccurs="0"/>
   <xs:element name="SegmentTemplate" type="SegmentTemplateType" minOccurs="0"/>
   </xs:sequence>
   <xs:attribute name="id" type="StringNoWhitespaceType" use="required"/>
   <xs:attribute name="bandwidth" type="xs:unsignedInt" use="required"/>
   <xs:attribute name="qualityRanking" type="xs:unsignedInt"/>
   <xs:attribute name="dependencyId" type="StringVectorType"/>
   <xs:attribute name="mediaStreamStructureId" type="StringVectorType"/>
   </xs:extension>
   </xs:complexContent>
   </xs:complexType>
   * */
  export interface Representation extends Element, RepresentationBase {
    readonly eBaseURLs?: readonly BaseURL[]                     // <xs:element name="BaseURL" type="BaseURLType" minOccurs="0" maxOccurs="unbounded"/>
    // SubRepresentation:                            // <xs:element name="SubRepresentation" type="SubRepresentationType" minOccurs="0" maxOccurs="unbounded"/>
    // SegmentBase:                                  // <xs:element name="SegmentBase" type="SegmentBaseType" minOccurs="0"/>
    // SegmentList:                                  // <xs:element name="SegmentList" type="SegmentListType" minOccurs="0"/>
    readonly eSegmentTemplate?: SegmentTemplate        // <xs:element name="SegmentTemplate" type="SegmentTemplateType" minOccurs="0"/>
    // readonly aId: StringNoWhitespaceType                      // <xs:attribute name="id" type="StringNoWhitespaceType" use="required"/>
    // readonly aBandwidth: number                               // <xs:attribute name="bandwidth" type="xs:unsignedInt" use="required"/>
    /** qualityRanking
     类型：整数
     作用：表示该 Representation 在 同一 AdaptationSet 内的画质等级顺序
     含义：
     - 值越小 → 画质越低（低码率/低分辨率）
     - 值越大 → 画质越高（高码率/高分辨率）
     用途：
     - 播放器可根据网络状况选择 合适的 Representation
     - 对于 多层增强（Scalable Video Coding, SVC），这个属性指示层次优先级

     示例:
     <Representation id="360p" bandwidth="800000" qualityRanking="1"/>
     <Representation id="720p" bandwidth="2000000" qualityRanking="2"/>
     <Representation id="1080p" bandwidth="5000000" qualityRanking="3"/>
     */
    // readonly aQualityRanking?: number                        // <xs:attribute name="qualityRanking" type="xs:unsignedInt"/>

    /** dependencyId
     类型：字符串或列表
     作用：指示该 Representation 依赖于哪个 Representation / SubRepresentation
     含义：
     - 在 SVC 或多轨道增强中，有些层或轨道必须依赖其他轨道
     - 播放器在请求该 Representation 时，必须先获取依赖的 Representation
     用途：
     - 支持 分层解码
     - 避免播放器单独播放增强层导致无法解码

     示例:
     <Representation id="enhancement" dependencyId="base"/>
     */
    // aDependencyId?: StringVectorType                // <xs:attribute name="dependencyId" type="StringVectorType"/>

    /** mediaStreamStructureId
     类型：字符串
     作用：标识该 Representation 属于哪条媒体流结构（stream structure）
     含义：
     - 主要用于 复杂 DASH 流 / 多角度 / 多轨道同步
     - 同一 mediaStreamStructureId 下的 Representation 共享解码时间轴或流逻辑
     用途：
     - 播放器可以把属于同一结构的 Representation 当作一条逻辑流处理
     - 有助于 多轨道同步播放 或 多层视频解码

     示例:
     <Representation id="360p" mediaStreamStructureId="video_stream1"/>
     <Representation id="base" mediaStreamStructureId="video_stream1"/>
     <Representation id="enhancement" mediaStreamStructureId="video_stream1"/>
     */
    // aMediaStreamStructureId?: StringVectorType      // <xs:attribute name="mediaStreamStructureId" type="StringVectorType"/>
  }

  /**
   <!--  Segment information base  -->
   <xs:complexType name="SegmentBaseType">
   <xs:sequence>
   <xs:element name="Initialization" type="URLType" minOccurs="0"/>
   <xs:element name="RepresentationIndex" type="URLType" minOccurs="0"/>
   <xs:any namespace="##other" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence>
   <xs:attribute name="timescale" type="xs:unsignedInt"/>
   <xs:attribute name="presentationTimeOffset" type="xs:unsignedLong"/>
   <xs:attribute name="indexRange" type="xs:string"/>
   <xs:attribute name="indexRangeExact" type="xs:boolean" default="false"/>
   <xs:attribute name="availabilityTimeOffset" type="xs:double"/>
   <xs:attribute name="availabilityTimeComplete" type="xs:boolean"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   * */
  export interface SegmentBase extends Element {
    readonly eInitialization?: URLType             // <xs:element name="Initialization" type="URLType" minOccurs="0"/>
    readonly eRepresentationIndex?: URLType        // <xs:element name="RepresentationIndex" type="URLType" minOccurs="0"/>
    // aTimescale?: number                // <xs:attribute name="timescale" type="xs:unsignedInt"/>
  }

  /**
   <!--  Multiple Segment information base  -->
   <xs:complexType name="MultipleSegmentBaseType">
   <xs:complexContent>
   <xs:extension base="SegmentBaseType">
   <xs:sequence>
   <xs:element name="SegmentTimeline" type="SegmentTimelineType" minOccurs="0"/>
   <xs:element name="BitstreamSwitching" type="URLType" minOccurs="0"/>
   </xs:sequence>
   <xs:attribute name="duration" type="xs:unsignedInt"/>
   <xs:attribute name="startNumber" type="xs:unsignedInt"/>
   </xs:extension>
   </xs:complexContent>
   </xs:complexType>
   * */
  export interface MultipleSegmentBase extends SegmentBase {
    readonly eSegmentTimeline?: SegmentTimeline    // <xs:element name="SegmentTimeline" type="SegmentTimelineType" minOccurs="0"/>
    // readonly aDuration?: number                        // <xs:attribute name="duration" type="xs:unsignedInt"/>
    readonly aStartNumber?: number                     // <xs:attribute name="startNumber" type="xs:unsignedInt"/>
  }

  // /**
  //  <!--  Segment List  -->
  //  <xs:complexType name="SegmentListType">
  //    <xs:complexContent>
  //      <xs:extension base="MultipleSegmentBaseType">
  //      <xs:sequence>
  //       <xs:element name="SegmentURL" type="SegmentURLType" minOccurs="0" maxOccurs="unbounded"/>
  //      </xs:sequence>
  //      <xs:attribute ref="xlink:href"/>
  //      <xs:attribute ref="xlink:actuate" default="onRequest"/>
  //      </xs:extension>
  //    </xs:complexContent>
  //  </xs:complexType>
  //  * */
  // export interface SegmentListElement extends MultipleSegmentBaseType {
  //
  // }

  /**
   <!--  Segment Template  -->
   <xs:complexType name="SegmentTemplateType">
   <xs:complexContent>
   <xs:extension base="MultipleSegmentBaseType">
   <xs:attribute name="media" type="xs:string"/>
   <xs:attribute name="index" type="xs:string"/>
   <xs:attribute name="initialization" type="xs:string"/>
   <xs:attribute name="bitstreamSwitching" type="xs:string"/>
   </xs:extension>
   </xs:complexContent>
   </xs:complexType>
   * */
  export interface SegmentTemplate extends MultipleSegmentBase {
    readonly aMedia?: string                           // <xs:attribute name="media" type="xs:string"/>
    readonly aIndex?: string                           // <xs:attribute name="index" type="xs:string"/>
    readonly aInitialization?: string                  // <xs:attribute name="initialization" type="xs:string"/>
    // bitstreamSwitching?: string
  }

  /**
   <!--  Segment Timeline  -->
   <xs:complexType name="SegmentTimelineType">
   <xs:sequence>
   <xs:element name="S" minOccurs="1" maxOccurs="unbounded">
   <xs:complexType>
   <xs:attribute name="t" type="xs:unsignedLong"/>
   <xs:attribute name="n" type="xs:unsignedLong" use="optional"/>
   <xs:attribute name="d" type="xs:unsignedLong" use="required"/>
   <xs:attribute name="r" type="xs:integer" use="optional" default="0"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   </xs:element>
   <xs:any namespace="##other" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   * */
  export interface SegmentTimeline extends Element {
    readonly eSs: readonly S[]    // <xs:element name="S" minOccurs="1" maxOccurs="unbounded">
  }

  /**
   <xs:element name="S" minOccurs="1" maxOccurs="unbounded">
   <xs:complexType>
   <xs:attribute name="t" type="xs:unsignedLong"/>
   <xs:attribute name="n" type="xs:unsignedLong" use="optional"/>
   <xs:attribute name="d" type="xs:unsignedLong" use="required"/>
   <xs:attribute name="r" type="xs:integer" use="optional" default="0"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   </xs:element>

   | 属性    | use        | 是否必填 | 说明                                                     |
   | ----- | ---------- | ---- | ------------------------------------------------------ |
   | **t** | 默认（未写 use） | 可选   | 分片起始时间（单位由 timescale 定义），如果不写，播放器会按前一个 `<S>` 的结束时间顺序排列 |
   | **n** | optional   | 可选   | 重复次数，表示该 `<S>` 元素重复多少次 `d` 时长的片段，默认值是 0（即不重复）          |
   | **d** | required   | 必填   | 该分片的持续时间（duration），单位是 timescale 指定的时间单位               |
   | **r** | optional   | 可选   | 重复次数（可为负数表示倒序重复），默认 0                                  |

   注意：在 XSD 中，use="required" → 必填；
   use="optional" 或未写 use → 可选；
   default="值" → 如果不出现，使用默认值。
   * */
  export interface S extends Element {
    // readonly aT?: number   // <xs:attribute name="t" type="xs:unsignedLong"/>
    // readonly aN?: number   // <xs:attribute name="n" type="xs:unsignedLong" use="optional"/>
    // readonly aD: number    // <xs:attribute name="d" type="xs:unsignedLong" use="required"/>
    // readonly aR: number    // <xs:attribute name="r" type="xs:integer" use="optional" default="0"/>
  }

  /**
   <!--  Presentation Type enumeration  -->
   <xs:simpleType name="PresentationType">
   <xs:restriction base="xs:string">
   <xs:enumeration value="static"/>
   <xs:enumeration value="dynamic"/>
   </xs:restriction>
   </xs:simpleType>
   * */
  export enum PresentationType {
    STATIC = 'static',    // <xs:enumeration value="static"/>
    DYNAMIC = 'dynamic',  // <xs:enumeration value="dynamic"/>
  }

  /**
   <!--  Base URL  -->
   <xs:complexType name="BaseURLType">
   <xs:simpleContent>
   <xs:extension base="xs:anyURI">
   <xs:attribute name="serviceLocation" type="xs:string"/>
   <xs:attribute name="byteRange" type="xs:string"/>
   <xs:attribute name="availabilityTimeOffset" type="xs:double"/>
   <xs:attribute name="availabilityTimeComplete" type="xs:boolean"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:extension>
   </xs:simpleContent>
   </xs:complexType>
   * */
  export interface BaseURL extends Element {
    // 注意 value 中可能包含换行
    // 在使用时要记得 trim();
    readonly value: string                          // <BaseURL>http://cdn.example.com/video/</BaseURL>
    // aServiceLocation?: string              // <xs:attribute name="serviceLocation" type="xs:string"/>
    readonly aByteRange?: string                    // <xs:attribute name="byteRange" type="xs:string"/>
    // aAvailabilityTimeOffset?: number       // <xs:attribute name="availabilityTimeOffset" type="xs:double"/>
    // aAvailabilityTimeComplete?: boolean    // <xs:attribute name="availabilityTimeComplete" type="xs:boolean"/>
  }

  /**
   <!--  Type for Frame Rate  -->
   <xs:simpleType name="FrameRateType">
   <xs:restriction base="xs:string">
   <xs:pattern value="[0-9]*[0-9](/[0-9]*[0-9])?"/>
   </xs:restriction>
   </xs:simpleType>
   * */
  export type FrameRateType = string

  /**
   <!--  Whitespace-separated list of strings  -->
   <xs:simpleType name="StringVectorType">
   <xs:list itemType="xs:string"/>
   </xs:simpleType>
   * */
  export interface StringVectorType {
    readonly list: readonly string[]
  }

  /**
   <!--  String without white spaces  -->
   <xs:simpleType name="StringNoWhitespaceType">
   <xs:restriction base="xs:string">
   <xs:pattern value="[^\r\n\t \p{Z}]*"/>
   </xs:restriction>
   </xs:simpleType>
   */
  export type StringNoWhitespaceType = string

  /**
   <!--  Ratio Type for sar and par  -->
   <xs:simpleType name="RatioType">
   <xs:restriction base="xs:string">
   <xs:pattern value="[0-9]*:[0-9]*"/>
   </xs:restriction>
   </xs:simpleType>
   * */
  export type RatioType = string

  /**
   <!--  Segment Info item URL/range  -->
   <xs:complexType name="URLType">
   <xs:sequence>
   <xs:any namespace="##other" processContents="lax" minOccurs="0" maxOccurs="unbounded"/>
   </xs:sequence>
   <xs:attribute name="sourceURL" type="xs:anyURI"/>
   <xs:attribute name="range" type="xs:string"/>
   <xs:anyAttribute namespace="##other" processContents="lax"/>
   </xs:complexType>
   * */
  export interface URLType extends Element {
    readonly aSourceURL?: AnyURI   // <xs:attribute name="sourceURL" type="xs:anyURI"/>
    readonly aRange?: string       // <xs:attribute name="range" type="xs:string"/>
  }

  export type AnyURI = string
}