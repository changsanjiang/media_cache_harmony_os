import { DashDefines } from "../../defines/DashDefines";
import { MCRange } from "../../utils/MCRange";
import { XmlUtils } from "./XmlUtils";

export namespace DashParser {
  /** MPD 解析 */
  export function parse(xmlText: string): DashDefines.MPDElement {
    const ranges = XmlUtils.findElementRanges(xmlText, "MPD");
    const mpdXmlRange = ranges && ranges.length == 1 ? ranges[0] : null;
    if ( !mpdXmlRange ) {
      throw new Error("Invalid MPD: missing or multiple <MPD> root elements");
    }

    const mpdXml = XmlUtils.extractText(xmlText, mpdXmlRange);
    const mpdXmlElement = XmlUtils.parseElement(mpdXml);
    if ( !mpdXmlElement ) {
      throw new Error("Invalid MPD: failed to parse <MPD> element");
    }

    const type = mpdXmlElement.attributes['type'];
    if ( type == DashDefines.PresentationType.DYNAMIC ) {
      throw new Error("Unsupported MPD type: dynamic (live not supported yet)"); // 目前暂不支持解析直播类型的配置文件
    }

    const innerText = mpdXmlElement.innerText;
    const innerTextRange = mpdXmlElement.innerTextRange;
    if ( !innerText || !innerTextRange ) {
      return {
        aType: DashDefines.PresentationType.STATIC,
        xmlRange: mpdXmlRange
      };
    }

    const baseURLs = parseBaseURLs(innerText, innerTextRange.location);
    const periods = parsePeriods(innerText, innerTextRange.location);
    return {
      eBaseURLs: baseURLs,
      ePeriods: periods,
      aType: DashDefines.PresentationType.STATIC,
      xmlRange: mpdXmlRange
    };
  }

  /** 解析所有 BaseURL 节点;
   *
   * xmlText:
   * <BaseURL>...</BaseURL>
   * <BaseURL>...</BaseURL>
   * */
  function parseBaseURLs(xmlText: string, xmlLocation: number): DashDefines.BaseURLElement[] | undefined {
    const baseURLRanges = XmlUtils.findElementRanges(xmlText, "BaseURL");
    if ( !baseURLRanges || baseURLRanges.length == 0 ) {
      return undefined;
    }

    return baseURLRanges.map(range =>
      parseBaseURL(
          XmlUtils.extractText(xmlText, range),
          range.location + xmlLocation,
      )
    );
  }

  /** 解析所有 Period 节点;
   *
   * xmlText:
   * <Period>...</Period>
   * <Period>...</Period>
   * */
  function parsePeriods(xmlText: string, xmlLocation: number): DashDefines.PeriodElement[] | undefined {
    const periodRanges = XmlUtils.findElementRanges(xmlText, "Period");
    if ( !periodRanges || periodRanges.length == 0 ) {
      return undefined;
    }

    return periodRanges.map(range =>
      parsePeriod(
        XmlUtils.extractText(xmlText, range),
        range.location + xmlLocation
      )
    );
  }

  /** 解析单个 BaseURL;
   *
   * xmlText:
   * <BaseURL serviceLocation="cdn1" byteRange="0-100">
   * http://cdn.example.com/video/
   * </BaseURL> */
  function parseBaseURL(xmlText: string, xmlLocation: number): DashDefines.BaseURLElement {
    const xmlElement = XmlUtils.parseElement(xmlText);
    if ( !xmlElement ) {
      throw new Error("Invalid BaseURL element: parse failed");
    }

    const value = xmlElement.innerText;
    const valueXmlRange = xmlElement.innerTextRange;
    if ( !value || !valueXmlRange ) {
      throw new Error("Invalid BaseURL element: missing inner text");
    }

    const byteRange = xmlElement.attributes['byteRange'];
    return {
      value: value,
      valueXmlRange: new MCRange(xmlLocation + valueXmlRange.location, valueXmlRange.length),
      aByteRange: byteRange,
      xmlRange: new MCRange(xmlLocation, xmlText.length)
    };
  }

  /** 解析单个 Period 对象;
   *
   * xmlText:
   * <Period>...</Period>
   * */
  function parsePeriod(xmlText: string, xmlLocation: number): DashDefines.PeriodElement {
    const baseURLs = parseBaseURLs(xmlText, xmlLocation);
    const adaptationSets = parseAdaptationSets(xmlText, xmlLocation);

    return {
      eBaseURLs: baseURLs,
      eAdaptationSets: adaptationSets,
      xmlRange: new MCRange(xmlLocation, xmlText.length),
    }
  }

  /** 解析所有 AdaptationSet 节点;
   *
   * xmlText:
   * <AdaptationSet contentType="video">...</AdaptationSet>
   * <AdaptationSet contentType="audio">...</AdaptationSet>
   * */
  function parseAdaptationSets(xmlText: string, xmlLocation: number): DashDefines.AdaptationSetElement[] | undefined {
    return undefined;
    // throw new Error("AdaptationSets parsing not implemented yet");
  }

  /** 解析所有 Representation 节点;
   *
   * xmlText:
   * <Representation>...</Representation>
   * <Representation>...</Representation>
   * */


  /** 解析 SegmentBase 节点 */
  function parseSegmentBase(xmlText: string, xmlLocation: number): DashDefines.SegmentBaseElement | undefined {
    return undefined;
  }

  /** 解析 SegmentTemplate 节点 */
  function parseSegmentTemplate(xmlText: string, xmlLocation: number): DashDefines.SegmentTemplateElement | undefined {
    return undefined;
  }
}
