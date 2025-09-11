import { DashXmlNode, DashElement, DashRepresentationSelectionHandler } from '../../defines/DashDefines';
import { MCRange } from '../../utils/MCRange';
import { _AdaptationSet, _BaseURL, _Period, _Representation, _S, _SegmentTemplate,
  _SegmentTimeline } from './DashModel';
import { XmlParser } from './XmlParser';

export interface DashParseOptions {
  readonly mpdOriginalUrl: string;
  readonly mpdCurrentUrl: string;
  readonly shouldTrim?: boolean;
  readonly representationSelectionHandler?: DashRepresentationSelectionHandler;
}

export interface DashParseResult {
  /** 修剪或解析后的 MPD 对象 */
  mpd: DashElement.MPD;

  /** 修剪 XML 文本, 多码率流只能选择一个进行播放; */
  trimmedXml: string;
}

export class DashParser {
  private mParseOptions?: DashParseOptions = undefined;

  /** MPD 解析 */
  parse(
    rawXml: string,
    options?: DashParseOptions,
  ): DashParseResult {
    this.mParseOptions = options;

    const parseResult = XmlParser.parse(rawXml);
    const mpdNode = parseResult.rootNode;
    const compactXml = parseResult.compactXml;

    const mpdType = mpdNode.attributes?.get("type");
    if ( mpdType == DashElement.PresentationType.DYNAMIC ) {
      throw new Error("Unsupported MPD type: dynamic (live not supported yet)"); // 目前暂不支持解析直播类型的配置文件
    }

    const baseURLs = this.parseBaseURLs(mpdNode);
    const periods = this.parsePeriods(mpdNode);
    const mpd: DashElement.MPD = {
      eBaseURLs: baseURLs,
      ePeriods: periods,
      node: mpdNode,
    };

    const trimmedXml = periods ? this.trimMpdXmlIfNeeded(compactXml, periods, mpdNode) : compactXml;
    return {
      mpd,
      trimmedXml,
    };
  }

  /** 修剪 MPD XML; */
  private trimMpdXmlIfNeeded(
    mpdXmlText: string,
    periods: _Period[],
    nodeTree: DashXmlNode,
  ) {
    if ( !periods || periods.length === 0 ) {
      return mpdXmlText;
    }

    const opts = this.mParseOptions;
    if ( !opts || !opts.shouldTrim || !opts.representationSelectionHandler ) {
      return mpdXmlText;
    }

    let resultXml = mpdXmlText

    for ( const p of periods ) {
      const adaptationSets = p.eAdaptationSets;
      if ( !adaptationSets || adaptationSets.length === 0 ) continue;

      for ( const set of adaptationSets ) {
        if ( !set.eRepresentations || set.eRepresentations.length <= 1 ) continue;

        // 选择要保留的 Representation
        const selectedRepresentation = opts.representationSelectionHandler(opts.mpdOriginalUrl, opts.mpdCurrentUrl, set);

        const firstRepresentation = set.eRepresentations[0];
        const lastRepresentation = set.eRepresentations[set.eRepresentations.length - 1];

        // 计算全局起始索引
        const firstStartIndex = XmlParser.computeStartIndex(nodeTree, firstRepresentation.node);
        const selectedStartIndex = firstRepresentation != selectedRepresentation ? XmlParser.computeStartIndex(nodeTree, selectedRepresentation.node) : firstStartIndex;
        const lastStartIndex = lastRepresentation != selectedRepresentation ? XmlParser.computeStartIndex(nodeTree, lastRepresentation.node) : selectedStartIndex;

        // 前面需要删除的范围
        const prevRange = new MCRange(firstStartIndex, selectedStartIndex - firstStartIndex);

        // 后面需要删除的范围
        const nextLocation = selectedStartIndex + selectedRepresentation.node.length;
        const nextLength = lastStartIndex + lastRepresentation.node.length - nextLocation;
        const nextRange = new MCRange(nextLocation, nextLength);
        resultXml = this.removeRange(resultXml, nextRange);
        resultXml = this.removeRange(resultXml, prevRange);

        // 更新 AdaptationSet，只保留选中的 Representation
        set.eRepresentations = [selectedRepresentation];
      }
    }
    return resultXml;
  }

  private removeRange(xml: string, range: MCRange) {
    if ( range.length <= 0 ) return xml;
    return xml.slice(0, range.location) + xml.slice(range.max);
  }
}
