import { MCRange } from "../../utils/MCRange"

export namespace XmlUtils {
  /** 解析后的 XML 元素 */
  export interface ParsedElement {
    tagName: string;                 // 标签名
    attributes: Record<string, string>; // 属性集合
    value?: string;                  // innerText，如果有
  }

  /**
   * 查找 XML 文本中指定标签的元素范围
   * @param xmlText   XML 文本
   * @param tagName   标签名 (例如 "SegmentTimeline" 或 "BaseURL")
   * @returns         范围数组
   */
  export function findElementRanges(xmlText: string, tagName: string): MCRange[] {
    const ranges: MCRange[] = [];

    // 匹配 <tag>...</tag> 和自闭合标签 <tag .../>
    const regex = new RegExp(
      `<${tagName}\\b[^>]*>([\\s\\S]*?)<\\/${tagName}>|<${tagName}\\b[^>]*/\\s*>`,
      "gi"
    );

    let match: RegExpExecArray | null;
    while ((match = regex.exec(xmlText)) !== null) {
      const location = match.index;
      const length = regex.lastIndex - match.index;
      ranges.push(new MCRange(location, length));
    }

    return ranges;
  }

  /**
   * 根据 MCRange 从 XML 文本中提取片段
   * @param xmlText XML 文本
   * @param range   元素范围
   */
  export function extractText(xmlText: string, range: MCRange): string {
    return xmlText.substring(range.location, range.location + range.length);
  }

  /**
   * 解析单个 XML 元素片段
   * @param xmlFragment   标签的 XML 片段（例如 "<BaseURL>http://...</BaseURL>"）
   * @returns             解析后的对象，包含 tagName、attributes、value
   */
  export function parseElement(xmlFragment: string): ParsedElement | null {
    // 匹配普通标签 <tag ...>value</tag> 或自闭合标签 <tag .../>
    // 支持单/双引号属性，允许自闭合标签中间有空格
    const startTagRegex = /^<(\w+)([^>]*)>([\s\S]*?)<\/\1>$|^<(\w+)([^>]*)\/\s*>$/i;
    const match = startTagRegex.exec(xmlFragment);
    if (!match) return null;

    // 提取标签名
    const tagName = match[1] || match[4];

    // 提取属性部分
    const attrsText = match[2] || match[5] || "";
    const attributes: Record<string, string> = {};
    const attrRegex = /(\w+)=["']([^"']*)["']/g;
    let attrMatch: RegExpExecArray | null;
    while ((attrMatch = attrRegex.exec(attrsText)) !== null) {
      attributes[attrMatch[1]] = attrMatch[2];
    }

    // 提取 innerText
    const value = match[3] || undefined;

    return { tagName, attributes, value };
  }
}