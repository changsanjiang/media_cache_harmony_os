import { DashDefines } from '../../defines/DashDefines';
import { XmlUtils } from './XmlUtils';

export namespace DashUtils {
  /** MPD 解析 */
  export function parse(xmlText: string): DashDefines.MPD {
    const nodeTree = XmlUtils.parseXmlToTree(xmlText);
    const mpdNodes = XmlUtils.findDirectChildrenByTagName(nodeTree, "MPD");
    const mpdNode = mpdNodes && mpdNodes.length == 1 ? mpdNodes[0] : undefined;
    if ( !mpdNode ) {
      throw new Error("Invalid MPD: missing or multiple <MPD> root elements");
    }

    const mpdType = mpdNode.attributes?.get("type");
    if ( mpdType == DashDefines.PresentationType.DYNAMIC ) {
      throw new Error("Unsupported MPD type: dynamic (live not supported yet)"); // 目前暂不支持解析直播类型的配置文件
    }

    const childNodes = mpdNode.children;
    if ( childNodes.length == 0 ) {
      throw new Error("xxx");
    }

    const baseURLs = parseBaseURLs(mpdNode);
    const periods = parsePeriods(mpdNode);
    return {
      eBaseURLs: baseURLs,
      ePeriods: periods,
      aType: DashDefines.PresentationType.STATIC,
    };
  }

  /** 解析所有 BaseURL 节点;
   *
   * xmlText:
   * <Parent>
   *  <BaseURL>...</BaseURL>
   *  <BaseURL>...</BaseURL>
   * </Parent>
   * */
  function parseBaseURLs(parentNode: DashDefines.XmlNode): DashDefines.BaseURL[] | undefined {
    const baseURLNodes = XmlUtils.findDirectChildrenByTagName(parentNode, "BaseURL");
    if ( baseURLNodes.length == 0 ) {
      return undefined;
    }
    return baseURLNodes.map(node => parseBaseURL(node));
  }

  /** 解析单个 BaseURL 节点;
   *
   * xmlText:
   * <BaseURL serviceLocation="cdn1" byteRange="0-100">
   *  http://cdn.example.com/video/
   * </BaseURL>
   * */
  function parseBaseURL(baseURLNode: DashDefines.XmlNode): DashDefines.BaseURL {
    const value = baseURLNode.innerText;
    const valueXmlRange = baseURLNode.innerTextRange;
    if ( !value || !valueXmlRange ) {
      throw new Error("Invalid BaseURL element: missing inner text");
    }

    const byteRange = baseURLNode.attributes?.get('byteRange');
    return {
      value: value,
      valueXmlRange: valueXmlRange,
      aByteRange: byteRange,
    };
  }

  /** 解析所有 Period 节点;
   *
   * xmlText:
   * <Parent>
   *  <Period>...</Period>
   *  <Period>...</Period>
   * </Parent>
   * */
  function parsePeriods(parentNode: DashDefines.XmlNode): DashDefines.Period[] | undefined {
    const periodNodes = XmlUtils.findDirectChildrenByTagName(parentNode, "Period");
    if ( periodNodes.length == 0 ) {
      return undefined;
    }
    return periodNodes.map(node => parsePeriod(node));
  }

  /** 解析单个 Period 节点;
   *
   * xmlText:
   * <Period>...</Period>
   * */
  function parsePeriod(periodNode: DashDefines.XmlNode): DashDefines.Period {
    const baseURLs = parseBaseURLs(periodNode);
    const adaptationSets = parseAdaptationSets(periodNode);
    return {
      eBaseURLs: baseURLs,
      eAdaptationSets: adaptationSets,
    }
  }

  /** 解析所有 AdaptationSet 节点;
   *
   * xmlText:
   * <Parent>
   *  <AdaptationSet contentType="video">...</AdaptationSet>
   *  <AdaptationSet contentType="audio">...</AdaptationSet>
   * </Parent>
   * */
  function parseAdaptationSets(parentNode: DashDefines.XmlNode): DashDefines.AdaptationSet[] | undefined {
    const adaptationSetNodes = XmlUtils.findDirectChildrenByTagName(parentNode, "AdaptationSet");
    if ( adaptationSetNodes.length == 0 ) {
      return undefined;
    }
    return adaptationSetNodes.map(node => parseAdaptationSet(node));
  }

  /** 解析单个 AdaptationSet 节点;
   *
   * <AdaptationSet contentType="video">...</AdaptationSet>
   * */
  function parseAdaptationSet(adaptationSetNode: DashDefines.XmlNode): DashDefines.AdaptationSet {
    const baseURLs = parseBaseURLs(adaptationSetNode);
    const representations = parseRepresentations(adaptationSetNode);
    return {
      eBaseURLs: baseURLs,
      eRepresentations: representations,
      aContentType: adaptationSetNode.attributes?.get("contentType")
    }
  }

  /** 解析所有 Representation 节点;
   *
   * xmlText:
   * <Parent>
   *  <Representation>...</Representation>
   *  <Representation>...</Representation>
   * </Parent>
   * */
  function parseRepresentations(parentNode: DashDefines.XmlNode): DashDefines.Representation[] | undefined {
    const representationNodes = XmlUtils.findDirectChildrenByTagName(parentNode, "Representation");
    if ( representationNodes.length == 0 ) {
      return undefined;
    }
    return representationNodes.map(node => parseRepresentation(node));
  }

  /** 解析单个 Representation 节点;
   *
   * <Representation id="360p" bandwidth="800000" qualityRanking="1"/>
   * */
  function parseRepresentation(representationNode: DashDefines.XmlNode): DashDefines.Representation {
    const baseURLs = parseBaseURLs(representationNode);
    const segmentTemplate = parseSegmentTemplate(representationNode);

    return {
      eBaseURLs: baseURLs,
      eSegmentTemplate: segmentTemplate,
      aId: representationNode.attributes?.get("id")!,
      aBandwidth: toInt(representationNode.attributes?.get("bandwidth"))!,
      aQualityRanking: toInt(representationNode.attributes?.get("qualityRanking")),
      aWidth: toInt(representationNode.attributes?.get("width")),
      aHeight: toInt(representationNode.attributes?.get("height")),
      aFrameRate: representationNode.attributes?.get("frameRate"),
      aAudioSamplingRate: representationNode.attributes?.get("audioSamplingRate"),
      aMimeType: representationNode.attributes?.get("mimeType"),
      aSegmentProfiles: representationNode.attributes?.get("segmentProfiles"),
      aCodecs: representationNode.attributes?.get("codecs"),
    };
  }

  // /** 解析 SegmentBase 节点 */
  // function parseSegmentBase(xmlText: string, xmlLocation: number): DashDefines.SegmentBaseElement | undefined {
  //   return undefined;
  // }

  /** 解析 SegmentTemplate 节点 */
  function parseSegmentTemplate(parentNode: DashDefines.XmlNode): DashDefines.SegmentTemplate | undefined {
    const segmentTemplateNodes = XmlUtils.findDirectChildrenByTagName(parentNode, "SegmentTemplate");
    if ( segmentTemplateNodes.length == 0 ) {
      return undefined;
    }

    if ( segmentTemplateNodes.length > 1 ) {
      throw new Error("xxx");
    }

    const segmentTemplateNode = segmentTemplateNodes[0];

    return {
      // eInitialization:
      // eRepresentationIndex:
      eSegmentTimeline: parseSegmentTimeline(segmentTemplateNode),
      aDuration: toInt(segmentTemplateNode.attributes?.get("duration")),
      aStartNumber: toInt(segmentTemplateNode.attributes?.get("startNumber")),
      aMedia: segmentTemplateNode.attributes?.get("media"),
      aIndex: segmentTemplateNode.attributes?.get("index"),
      aInitialization: segmentTemplateNode.attributes?.get("initialization"),
    };
  }

  /** 解析 SegmentTimeline 节点 */
  function parseSegmentTimeline(parentNode: DashDefines.XmlNode): DashDefines.SegmentTimeline | undefined {
    const segmentTimelineNodes = XmlUtils.findDirectChildrenByTagName(parentNode, "SegmentTemplate");
    if ( segmentTimelineNodes.length == 0 ) {
      return undefined;
    }

    if ( segmentTimelineNodes.length > 1 ) {
      throw new Error("xxx");
    }

    const segmentTimelineNode = segmentTimelineNodes[0];
    return {
      eSs: parseSs(segmentTimelineNode),
    }
  }

  /** 解析所有的 S 节点 */
  function parseSs(parentNode: DashDefines.XmlNode): DashDefines.S[] {
    const sNodes = XmlUtils.findDirectChildrenByTagName(parentNode, "S");
    if ( sNodes.length == 0 ) {
      throw new Error("xxx");
    }
    return sNodes.map(node => parseS(node));
  }

  /** 解析 S 节点 */
  function parseS(sNode: DashDefines.XmlNode): DashDefines.S {
    return {
      aT: toInt(sNode.attributes?.get("t")),
      aN: toInt(sNode.attributes?.get("n")),
      aD: toInt(sNode.attributes?.get("d"))!,
      aR: toInt(sNode.attributes?.get("r"))!,
    };
  }

  function toInt(valueStr?: string): number | undefined {
    const str = valueStr?.trim();
    return str ? parseInt(str) : undefined;
  }
}
