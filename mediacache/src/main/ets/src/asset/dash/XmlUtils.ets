import { MCRange } from "../../utils/MCRange"
import { util, xml } from '@kit.ArkTS';

export namespace XmlUtils {
  /** XML 元素节点 */
  export interface XmlElementNode {
    readonly name: string;
    readonly depth: number;
    readonly children: XmlElementNode[]

    // 直接文本节点（不含子元素标签）的内容与范围
    innerText?: string;
    innerTextRange?: Range;

    range?: Range;                     // 整个元素的范围
    startTagRange?: Range;             // <tag ...> 的范围
    endTagRange?: Range;               // </tag> 的范围（自闭合元素可为空）
  }

  /** 解析后的 XML 元素 */
  export interface ParsedElement {
    tagName: string;                 // 标签名
    attributes: Record<string, string>; // 属性集合
    innerText?: string;                  // innerText，如果有
    innerTextRange?: MCRange;            // innerText 在原始片段中的范围
  }

  interface Position {
    line: number;
    column: number;
  }

  interface Range {
    start: Position;
    end: Position;
  }

  /** 构建 element 树 */
  export function parseXmlToTree(xmlText: string): XmlElementNode {
    let textEncoder = new util.TextEncoder();
    let arrBuffer = textEncoder.encodeInto(xmlText);
    let parser = new xml.XmlPullParser(arrBuffer.buffer as object as ArrayBuffer);

    // 根节点占位
    const root: XmlElementNode = {
      name: "",
      depth: 0,
      children: []
    };

    const xmlTextLines = xmlText.split(/\r?\n/);

    const prevPosition: Position = {
      line: 0,
      column: 0,
    };

    const stack: XmlElementNode[] = [root];
    const options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (key, value) => {
        console.log(`AAAA: key=${xml.EventType[key]}, [${value.getLineNumber()}, ${value.getColumnNumber()}]`)

        switch (key) {
          case xml.EventType.START_TAG: {
            const element: XmlElementNode = {
              name: value.getName(),
              depth: value.getDepth(),
              children: []
            };
            // 将新节点加入栈顶父节点的 children
            const parent = stack[stack.length - 1];
            parent.children.push(element);
            // 当前节点入栈
            stack.push(element);

            element.startTagRange = {
              start: {
                line: prevPosition.line,
                column: prevPosition.column
              },
              end: {
                line: value.getLineNumber(),
                column: value.getColumnNumber(),
              }
            }
            break;
          }

          case xml.EventType.END_TAG: {
            // 弹出栈顶节点，记录结束行列
            const element = stack.pop();
            if ( element ) {
              // 判断是否是自闭标签
              const endIndex = positionToIndex(xmlTextLines, value.getLineNumber(), value.getColumnNumber());
              const substr = xmlText.substring(0, endIndex);
              const isSelfClosingTag = substr.endsWith("/>");
              if ( !isSelfClosingTag ) {
                element.endTagRange = {
                  start: {
                    line: prevPosition.line,
                    column: prevPosition.column
                  },
                  end: {
                    line: value.getLineNumber(),
                    column: value.getColumnNumber(),
                  }
                };
                element.range = {
                  start: element.startTagRange?.start!,
                  end: element.endTagRange.end,
                }
              }
              else {
                element.range = element.startTagRange;
              }
            }
            break;
          }

          case xml.EventType.TEXT: {
            // 直接文本节点
            const parent = stack[stack.length - 1];
            if ( parent ) {
              parent.innerText = value.getText();
              parent.innerTextRange = {
                start: {
                  line: prevPosition.line,
                  column: prevPosition.column
                },
                end: {
                  line: value.getLineNumber(),
                  column: value.getColumnNumber(),
                }
              }
            }
            break;
          }

          default:
            break;
        }

        prevPosition.line = value.getLineNumber();
        prevPosition.column = value.getColumnNumber();
        return true;
      }
    };

    parser.parseXml(options);
    return root;
  }

  /**
   * 查找 XML 文本中指定标签的元素范围
   * @param xmlText   XML 文本
   * @param tagName   标签名 (例如 "SegmentTimeline" 或 "BaseURL")
   * @returns         范围数组
   */
  export function findElementRanges(xmlText: string, tagName: string): MCRange[] {
    const ranges: MCRange[] = [];

    return ranges;
  }

  /**
   * 根据 MCRange 从 XML 文本中提取片段
   * @param xmlText XML 文本
   * @param range   元素范围
   */
  export function extractText(xmlText: string, range: MCRange): string {
    return xmlText.substring(range.location, range.max);
  }

  /**
   * 解析单个 XML 元素片段
   * @param xmlFragment   标签的 XML 片段（例如 "<BaseURL>http://...</BaseURL>"）
   * @returns             解析后的对象，包含 tagName、attributes、value
   */
  export function parseElement(xmlFragment: string, baseOffset = 0): ParsedElement | undefined {
    // 匹配普通标签 <tag ...>value</tag> 或自闭合标签 <tag .../>
    // 支持单/双引号属性，允许自闭合标签中间有空格
    const startTagRegex = /^<(\w+)([^>]*)>([\s\S]*?)<\/\1>$|^<(\w+)([^>]*)\/\s*>$/i;
    const match = startTagRegex.exec(xmlFragment);
    if (!match) return undefined;

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

    // 提取 innerText 和范围
    const innerText = match[3] || undefined;
    let innerTextRange: MCRange | undefined;
    if (innerText !== undefined) {
      // match[0] = 整个片段，match[3] = innerText
      const startIndex = xmlFragment.indexOf(innerText, 0);
      innerTextRange = new MCRange(baseOffset + startIndex, innerText.length);
    }

    return { tagName, attributes, innerText, innerTextRange };
  }

  export function getXmlElementRange(
    name: string,
    xmlText: string,
    xmlTextLines: string[],
    startTagEndLineNumber: number,
    startTagEndColumnNumber: number,
    endTagEndLineNumber: number,
    endTagEndColumnNumber: number,
  ): MCRange {
    const startTagEndIndex = positionToIndex(xmlTextLines, startTagEndLineNumber, startTagEndColumnNumber);
    const tagPrefix = `<${name}`;

    // 从 startTagEndIndex 向前查找起始 <tag
    const elementStartIndex = xmlText.slice(0, startTagEndIndex).lastIndexOf(tagPrefix);
    if (elementStartIndex === -1) {
      throw new Error(`Cannot find start tag <${name}> before line ${startTagEndLineNumber}, column ${startTagEndColumnNumber}`);
    }

    // self-closing tag 判断
    const isSelfClosing = startTagEndLineNumber === endTagEndLineNumber && startTagEndColumnNumber === endTagEndColumnNumber;
    if (isSelfClosing) {
      return new MCRange(elementStartIndex, startTagEndIndex - elementStartIndex);
    }

    const elementEndIndex = positionToIndex(xmlTextLines, endTagEndLineNumber, endTagEndColumnNumber);
    if (elementEndIndex < elementStartIndex) {
      throw new Error(`End tag position is before start tag for <${name}>`);
    }

    return new MCRange(elementStartIndex, elementEndIndex - elementStartIndex);
  }

  /**
   * 从指定位置向前搜索 target
   * @param source - 整段文本
   * @param startIdx - 起始绝对索引（0-based）
   * @param target - 要搜索的字符串
   * @returns 匹配的绝对索引，如果没找到返回 -1
   */
  export function searchBackward(
    source: string,
    startIdx: number,
    target: string
  ): number {
    if (!target || startIdx <= 0) return -1;

    // 确保起点不超过文本长度
    const endIdx = Math.min(startIdx, source.length);

    // 截取从开头到起点的子串
    const subStr = source.slice(0, endIdx);

    // 向前搜索
    return subStr.lastIndexOf(target); // 找不到返回 -1
  }

  /**
   * 计算指定 (lineNumber, columnNumber) 在多行文本中的绝对索引
   * @param lines - 文本的行数组
   * @param lineNumber - 行号（从 1 开始）
   * @param columnNumber - 列号（从 1 开始）
   * @returns 绝对索引（从 0 开始计数）
   */
  export function positionToIndex(
    lines: string[],
    lineNumber: number,
    columnNumber: number
  ): number {
    // 转成 0-based
    const lineIdx = lineNumber - 1;
    const colIdx = columnNumber - 1;

    if (lineIdx < 0 || lineIdx >= lines.length) {
      throw new Error(`Line number ${lineNumber} is out of range (1-${lines.length})`);
    }

    const currentLine = lines[lineIdx];
    if (colIdx < 0 || colIdx > currentLine.length) {
      throw new Error(`Column number ${columnNumber} is out of range (1-${currentLine.length}) for line ${lineNumber}`);
    }

    // 前面行的长度 + 换行符长度
    let index = 0;
    for ( let i = 0; i < lineIdx; ++i ) {
      index += lines[i].length + 1; // 每行末尾有一个 '\n'
    }

    // 加上当前列偏移
    index += colIdx;

    return index;
  }
}