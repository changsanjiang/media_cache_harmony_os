import { DashElement, DashRepresentationSelectionHandler, DashXmlNode } from '../../defines/DashDefines';
import MCArrayUtils from '../../utils/MCArrayUtils';
import { MCRange } from '../../utils/MCRange';
import MCUtils from '../../utils/MCUtils';
import { DashProxyUtils } from './DashProxyUtils';
import { XmlParser } from './XmlParser';
import { url } from '@kit.ArkTS';

export interface DashParseOptions {
  readonly mpdOriginalUrl: string;
  readonly mpdCurrentUrl: string;
  readonly shouldTrim?: boolean;
  readonly representationSelectionHandler?: DashRepresentationSelectionHandler;
}

export interface DashParseResult {
  mpd: DashElement.MPD;
  compactXml: string; // 删除了换行、空格
}

export namespace DashParser {
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
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): string {
    const result = parse(rawXml);
    const mpd = result.mpd as _MPD;
    const compactXml = result.compactXml;
    const periods = mpd.ePeriods;
    if ( !periods || periods.length === 0 ) {
      return compactXml;
    }

    const mpdNode = mpd.node;
    let proxyXml = compactXml
    for ( const p of periods ) {
      // 修剪, 多码率流仅能保留一个进行缓存
      proxyXml = trimPeriod(proxyXml, p, mpdNode, originalUrl, currentUrl, representationSelectionHandler);

      // 处理 BaseURL, 替换为代理地址
      proxyXml = proxyPeriod(proxyXml, mpd, p, currentUrl, assetId);
    }
    return proxyXml;
  }

  function trimPeriod(
    proxyXml: string,
    period: _Period,
    mpdNode: DashXmlNode,
    originalUrl: string,
    currentUrl: string,
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): string {
    const adaptationSets = period.eAdaptationSets;
    if ( !adaptationSets || adaptationSets.length === 0 )
      return proxyXml;

    // 处理多码率流, 只能保留一个流进行缓存
    for ( const set of adaptationSets ) {
      if ( !set.eRepresentations || set.eRepresentations.length <= 1 ) continue;

      // 选择要保留的 Representation
      const selectedRepresentation = selectRepresentation(originalUrl, currentUrl, set, representationSelectionHandler);

      const firstRepresentation = set.eRepresentations[0];
      const lastRepresentation = set.eRepresentations[set.eRepresentations.length - 1];

      // 计算全局起始索引
      const firstStartIndex = XmlParser.computeStartIndex(mpdNode, firstRepresentation.node);
      const selectedStartIndex = firstRepresentation != selectedRepresentation ? XmlParser.computeStartIndex(mpdNode, selectedRepresentation.node) : firstStartIndex;
      const lastStartIndex = lastRepresentation != selectedRepresentation ? XmlParser.computeStartIndex(mpdNode, lastRepresentation.node) : selectedStartIndex;

      // 前面需要删除的范围
      const prevRange = new MCRange(firstStartIndex, selectedStartIndex - firstStartIndex);

      // 后面需要删除的范围
      const nextLocation = selectedStartIndex + selectedRepresentation.node.length;
      const nextLength = lastStartIndex + lastRepresentation.node.length - nextLocation;
      const nextRange = new MCRange(nextLocation, nextLength);
      proxyXml = removeRange(proxyXml, nextRange);
      proxyXml = removeRange(proxyXml, prevRange);

      // 更新 AdaptationSet，只保留选中的 Representation
      set.eRepresentations = [selectedRepresentation];
    }
    return proxyXml;
  }

  function proxyPeriod(
    proxyXml: string,
    mpd: _MPD,
    period: _Period,
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

  // adaptationSet.eRepresentations 必定有值, 并且 length > 1;
  function selectRepresentation(
    originalUrl: string,
    currentUrl: string,
    adaptationSet: _AdaptationSet,
    representationSelectionHandler?: DashRepresentationSelectionHandler
  ): _Representation {
    const representations = adaptationSet.eRepresentations!;
    if ( representationSelectionHandler ) {
      const r = representationSelectionHandler(originalUrl, currentUrl, adaptationSet);
      if ( r ) return r;
    }
    return representations[Math.floor((representations.length / 2))];
  }

  function removeRange(xml: string, range: MCRange) {
    if ( range.length <= 0 ) return xml;
    return xml.slice(0, range.location) + xml.slice(range.max);
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
    readonly eAdaptationSets?: readonly _AdaptationSet[] | undefined;

    constructor(node: DashXmlNode) {
      super(node);

      this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
      this.eAdaptationSets = XmlParser.findDirectChildrenByTagName(node, "AdaptationSet").map(it => new _AdaptationSet(it));
    }
  }

  class _AdaptationSet extends _DashElement implements DashElement.AdaptationSet {
    readonly eBaseURLs?: readonly _BaseURL[] | undefined;
    eRepresentations?: readonly _Representation[];

    constructor(node: DashXmlNode) {
      super(node);

      this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
      this.eRepresentations = XmlParser.findDirectChildrenByTagName(node, "Representation").map(it => new _Representation(it));
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