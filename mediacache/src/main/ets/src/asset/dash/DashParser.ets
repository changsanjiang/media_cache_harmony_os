import {
  DashAdaptationSetSelectionHandler,
  DashElement,
  DashRepresentationSelectionHandler,
  DashXmlNode
} from '../../defines/DashDefines';
import MCArrayUtils from '../../utils/MCArrayUtils';
import MCUtils from '../../utils/MCUtils';
import { DashProxyUtils } from './DashProxyUtils';
import { XmlParser } from './XmlParser';
import { url } from '@kit.ArkTS';
import { text } from '@kit.ArkGraphics2D';

export namespace DashParser {
  export interface DashParseResult {
    mpd: DashElement.MPD;
    compactXml: string; // 删除了换行、空格
  }

  /** MPD 解析; */
  export function parse(rawXml: string): DashParseResult {
    const parseResult = XmlParser.parse(rawXml);
    const mpdNode = parseResult.rootNode;
    const compactXml = parseResult.compactXml;

    const mpdType = mpdNode.attributes?.get("type");
    if ( mpdType == DashElement.PresentationType.DYNAMIC ) {
      throw new Error("Unsupported MPD type: dynamic (live not supported yet)"); // 目前暂不支持解析直播类型的配置文件
    }

    const mpd = new _MPD(mpdNode);
    return {
      mpd,
      compactXml
    }
  }

  /** MPD 代理; */
  export function proxy(
    rawXml: string,
    assetId: string,
    originalUrl: string,
    currentUrl: string,
    adaptationSetSelectionHandler?: DashAdaptationSetSelectionHandler,
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): string {
    const result = parse(rawXml);
    const mpd = result.mpd as _MPD;
    const compactXml = result.compactXml;
    const periods = mpd.ePeriods;
    if ( !periods || periods.length === 0 ) {
      return compactXml;
    }

    let proxyXml = compactXml
    for ( const p of periods ) {
      // 修剪, 多码率流仅能保留一个进行缓存
      proxyXml = trimPeriod(proxyXml, p, mpd, originalUrl, currentUrl, adaptationSetSelectionHandler, representationSelectionHandler);

      // 处理 BaseURL, 替换为代理地址
      proxyXml = proxyPeriod(proxyXml, p, mpd, currentUrl, assetId);
    }
    return proxyXml;
  }

  function trimPeriod(
    proxyXml: string,
    period: _Period,
    mpd: _MPD,
    originalUrl: string,
    currentUrl: string,
    adaptationSetSelectionHandler?: DashAdaptationSetSelectionHandler,
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): string {
    proxyXml = trimAdaptationSets(proxyXml, period, mpd, originalUrl, currentUrl, adaptationSetSelectionHandler, representationSelectionHandler);
    return proxyXml;
  }

  function proxyPeriod(
    proxyXml: string,
    period: _Period,
    mpd: _MPD,
    currentUrl: string,
    assetId: string,
  ): string {
    const mpdNode = mpd.node;
    const periodNode = period.node;

    const baseUrl = url.URL.parseURL("../", currentUrl).toString();

    const allBaseURLNodes = XmlParser.findAllNodes(periodNode, "BaseURL").reverse()
    for ( const baseURLNode of allBaseURLNodes ) {
      const uri = baseURLNode.innerText
      if ( !uri ) continue;

      // 将基地址替换成代理地址
      const absUrl = url.URL.parseURL(uri, baseUrl).toString();
      const proxyPath = DashProxyUtils.generateBaseProxyPath(absUrl, assetId);
      const absStartIndex = XmlParser.computeStartIndex(mpdNode, baseURLNode);
      const location = absStartIndex + baseURLNode.startTagEndIndex;
      const length = uri.length;

      XmlParser.replaceInnerText(baseURLNode, proxyPath);
      proxyXml = MCUtils.replaceCharactersInRange(proxyXml, [location, length], proxyPath);
    }

    if ( period.eBaseURLs?.length == 0 ) {
      // 插入一个 BaseURL 的代理节点
      const proxyPath = DashProxyUtils.generateBaseProxyPath(baseUrl, assetId);
      const result = XmlParser.createBaseURLNode(proxyPath);
      const baseURLNode = result.node;
      const baseURLCompactXml = result.compactXml;

      period.eBaseURLs = [new _BaseURL(baseURLNode)];
      XmlParser.insertBaseURLNode(periodNode, baseURLNode);
      const absStartIndex = XmlParser.computeStartIndex(mpdNode, baseURLNode);

      const location = absStartIndex;
      proxyXml = MCUtils.replaceCharactersInRange(proxyXml, [location, 0], baseURLCompactXml);
    }
    return proxyXml;
  }

  function trimAdaptationSets(
    proxyXml: string,
    period: _Period,
    mpd: _MPD,
    originalUrl: string,
    currentUrl: string,
    adaptationSetSelectionHandler?: DashAdaptationSetSelectionHandler,
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): string {
    if ( !period.eAdaptationSets || period.eAdaptationSets.length == 0 ) {
      return proxyXml;
    }

    const adaptationSets = [...period.eAdaptationSets];
    const groups = MCArrayUtils.groupByKey(adaptationSets, (it) => (it.aContentType ?? '')); // 根据 contentType 进行分组
    const selectedSets: _AdaptationSet[] = [];

    // 移除多余轨道
    // 多音频轨道的, 仅保留一个音频轨道
    // 多字幕轨道的, 仅保留一个字幕轨道
    for ( let pair of groups ) {
      const contentType = pair[0];
      const sets = pair[1];
      if ( sets.length > 0 ) {
        selectedSets.push(selectAdaptationSet(originalUrl, currentUrl, contentType, sets, adaptationSetSelectionHandler));
      }
    }

    if ( selectedSets.length != adaptationSets.length ) {
      for ( let i = adaptationSets.length - 1; i >= 0; --i ) {
        const set = adaptationSets[i];
        if ( !selectedSets.includes(set) ) {
          proxyXml = removeXml(set.node, mpd.node, proxyXml);
          MCArrayUtils.removeAt(adaptationSets, i);
        }
      }

      period.eAdaptationSets = adaptationSets;
    }

    // 处理多码率流, 仅保留一个流
    for ( const set of adaptationSets ) {
      proxyXml = trimAdaptationSet(proxyXml, set, mpd, originalUrl, currentUrl, representationSelectionHandler);
    }
    return proxyXml;
  }

  function selectAdaptationSet(
    originalUrl: string,
    currentUrl: string,
    contentType: string,
    adaptationSets: readonly _AdaptationSet[], // 传入的 adaptationSets.length 必定大于 1;
    adaptationSetSelectionHandler?: DashAdaptationSetSelectionHandler,
  ): _AdaptationSet {
    if ( adaptationSets.length == 1 ) {
      return adaptationSets[0];
    }

    if ( adaptationSetSelectionHandler ) {
      const s = adaptationSetSelectionHandler(originalUrl, currentUrl, contentType, adaptationSets);
      if ( s ) return s;
    }
    return adaptationSets[0];
  }

  function trimAdaptationSet(
    proxyXml: string,
    set: _AdaptationSet,
    mpd: _MPD,
    originalUrl: string,
    currentUrl: string,
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): string {
    if ( !set.eRepresentations || set.eRepresentations.length <= 1 ) return proxyXml;

    // 选择要保留的 Representation
    const selectedRepresentation = selectRepresentation(originalUrl, currentUrl, set, set.eRepresentations, representationSelectionHandler);
    const mpdNode = mpd.node;
    for ( const representation of set.eRepresentations ) {
      if ( representation != selectedRepresentation ) {
        proxyXml = removeXml(representation.node, mpdNode, proxyXml);
      }
    }

    // 更新 AdaptationSet，只保留选中的 Representation
    set.eRepresentations = [selectedRepresentation];
    return proxyXml;
  }

  function selectRepresentation(
    originalUrl: string,
    currentUrl: string,
    adaptationSet: _AdaptationSet,
    representations: readonly _Representation[],
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): _Representation {
    if ( representationSelectionHandler ) {
      const r = representationSelectionHandler(originalUrl, currentUrl, adaptationSet, representations);
      if ( r ) return r;
    }
    return representations[Math.floor((representations.length / 2))];
  }

  function removeXml(target: DashXmlNode, mpd: DashXmlNode, xml: string): string {
    const startIndex = XmlParser.computeStartIndex(mpd, target);
    const endIndex = startIndex + target.length;
    return xml.slice(0, startIndex) + xml.slice(endIndex);
  }

  class _DashElement implements DashElement.Element {
    node: DashXmlNode;

    constructor(node: DashXmlNode) {
      this.node = node;
    }
  }

  class _MPD extends _DashElement implements DashElement.MPD {
    readonly eBaseURLs?: readonly _BaseURL[] | undefined;
    readonly ePeriods?: readonly _Period[] | undefined;

    constructor(node: DashXmlNode) {
      super(node);

      this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
      this.ePeriods = XmlParser.findDirectChildrenByTagName(node, "Period").map(it => new _Period(it));
    }
  }

  class _Period extends _DashElement implements DashElement.Period {
    eBaseURLs?: readonly _BaseURL[];
    eAdaptationSets?: readonly _AdaptationSet[] | undefined;

    constructor(node: DashXmlNode) {
      super(node);

      this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
      this.eAdaptationSets = XmlParser.findDirectChildrenByTagName(node, "AdaptationSet").map(it => new _AdaptationSet(it));
    }
  }

  class _AdaptationSet extends _DashElement implements DashElement.AdaptationSet {
    readonly eBaseURLs?: readonly _BaseURL[] | undefined;
    eRepresentations?: readonly _Representation[];
    readonly aLang?: string;
    readonly aContentType?: string;

    constructor(node: DashXmlNode) {
      super(node);

      this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
      this.eRepresentations = XmlParser.findDirectChildrenByTagName(node, "Representation").map(it => new _Representation(it));
      this.aLang = node.attributes?.get("lang");
      this.aContentType = node.attributes?.get("contentType");
    }
  }

  class _Representation extends _DashElement implements DashElement.Representation {
    readonly eBaseURLs?: readonly _BaseURL[] | undefined;
    readonly eSegmentTemplate?: _SegmentTemplate;

    constructor(node: DashXmlNode) {
      super(node);

      this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
      this.eSegmentTemplate = MCArrayUtils.firstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "SegmentTemplate").map(it => new _SegmentTemplate(it)));
    }
  }

  class _SegmentBase extends _DashElement implements DashElement.SegmentBase {
    readonly eInitialization?: _URLType;
    readonly eRepresentationIndex?: _URLType;

    constructor(node: DashXmlNode) {
      super(node);

      this.eInitialization = MCArrayUtils.firstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "Initialization").map(it => new _URLType(it)));
      this.eRepresentationIndex = MCArrayUtils.firstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "RepresentationIndex").map(it => new _URLType(it)));
    }
  }

  class _MultipleSegmentBase extends _SegmentBase implements DashElement.MultipleSegmentBase {
    readonly eSegmentTimeline?: _SegmentTimeline;
    readonly aStartNumber?: number;

    constructor(node: DashXmlNode) {
      super(node);

      this.aStartNumber = toInt(node.attributes?.get("startNumber"));
      this.eSegmentTimeline = MCArrayUtils.firstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "SegmentTimeline").map(it => new _SegmentTimeline(it)));
    }
  }

  class _SegmentTemplate extends _MultipleSegmentBase implements DashElement.SegmentTemplate {
    readonly aMedia?: string;
    readonly aIndex?: string;
    readonly aInitialization?: string;

    constructor(node: DashXmlNode) {
      super(node);
      this.aMedia = node.attributes?.get("media");
      this.aIndex = node.attributes?.get("index");
      this.aInitialization = node.attributes?.get("initialization");
    }
  }

  class _SegmentTimeline extends _DashElement implements DashElement.SegmentTimeline {
    readonly eSs: readonly _S[];

    constructor(node: DashXmlNode) {
      super(node);

      this.eSs = XmlParser.findDirectChildrenByTagName(node, "S").map(it => new _S(it));
    }
  }

  class _S extends _DashElement implements DashElement.S {

  }

  class _BaseURL extends _DashElement implements DashElement.BaseURL {
    value: string;
    aByteRange?: string | undefined;

    constructor(node: DashXmlNode) {
      super(node);
      this.value = node.innerText!;
    }
  }

  class _URLType extends _DashElement implements DashElement.URLType {
    aSourceURL?: DashElement.AnyURI;
    aRange?: string;
  }

  function toInt(valueStr?: string): number | undefined {
    const str = valueStr?.trim();
    return str ? parseInt(str) : undefined;
  }
}