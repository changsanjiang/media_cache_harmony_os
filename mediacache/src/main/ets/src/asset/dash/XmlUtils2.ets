import { util, xml } from '@kit.ArkTS';
import { MCRange } from '../../utils/MCRange';

export namespace XmlUtils {
  /** XML 元素节点 */
  export interface XmlElementNode {
    readonly tagName: string;
    readonly depth: number;
    readonly children: XmlElementNode[]

    readonly innerText?: string; // 直接文本节点（不含子元素标签）的内容与范围
    readonly innerTextRange?: MCRange;

    readonly range?: MCRange;                     // 整个元素的范围
    readonly startTagRange?: MCRange;             // <tag ...> 的范围
    readonly endTagRange?: MCRange;               // </tag> 的范围（自闭合元素时为空）

    readonly attributes?: Map<string, string>;
  }

  /** 构建 element 节点树 */
  export function parseXmlToTree(
    xmlText: string
  ): XmlElementNode {
    let textEncoder = new util.TextEncoder();
    let arrBuffer = textEncoder.encodeInto(xmlText);
    let parser = new xml.XmlPullParser(arrBuffer.buffer as object as ArrayBuffer);

    // 根节点占位
    const root = new _XmlElementNode("", 0);

    const xmlLines = xmlText.split(/\r?\n/);
    let prevPosition: XmlPosition = {
      line: 0,
      column: 0,
    };

    const stack: _XmlElementNode[] = [root];
    const options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,
      attributeValueCallbackFunction: (key, value) => {
        if ( stack.length > 0 ) {
          const element = stack[stack.length - 1];
          if ( element.attributes == undefined ) {
            element.attributes = new Map();
          }
          element.attributes.set(key, value);
        }
        return true;
      },
      tokenValueCallbackFunction: (key, value) => {
        const curPos: XmlPosition = {
          line: value.getLineNumber(),
          column: value.getColumnNumber(),
        };

        switch (key) {
          case xml.EventType.START_TAG: {
            const element = new _XmlElementNode(value.getName(), value.getDepth());
            element.startTagRange = toRange(xmlLines, prevPosition, curPos);

            // 将新节点加入栈顶父节点的 children
            const parent = stack[stack.length - 1];
            parent.children.push(element);
            // 当前节点入栈
            stack.push(element);
            break;
          }
          case xml.EventType.END_TAG: {
            // 弹出栈顶节点，记录结束行列
            const element = stack.pop();
            if ( element ) {
              const endIndex = positionToIndex(xmlLines, curPos);
              const endStr = xmlText.substring(endIndex - 2, endIndex);
              // 判断是否是自闭标签
              const isSelfClosingTag = (endStr == "/>");
              if ( !isSelfClosingTag ) {
                element.endTagRange = toRange(xmlLines, prevPosition, curPos);
                const startIndex = element.startTagRange!.location;
                element.range = new MCRange(startIndex, endIndex - startIndex);
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
              parent.innerTextRange = toRange(xmlLines, prevPosition, curPos);
            }
            break;
          }

          default:
            break;
        }

        prevPosition = curPos;
        return true;
      }
    };

    parser.parseXml(options);
    return root;
  }

  /**
   * 查找第一层（parent.children）中所有匹配 tagName 的节点
   * @param parent 父节点
   * @param tagName 标签名
   */
  export function findDirectChildrenByTagName(
    parent: XmlElementNode,
    tagName: string
  ): XmlElementNode[] {
    return parent.children.filter(node => node.tagName === tagName);
  }

  interface XmlPosition {
    readonly line: number;
    readonly column: number;
  }

  class _XmlElementNode implements XmlElementNode {
    tagName: string;
    depth: number;
    children: _XmlElementNode[] = [];
    innerText?: string | undefined;
    innerTextRange?: MCRange | undefined;
    range?: MCRange | undefined;
    startTagRange?: MCRange | undefined;
    endTagRange?: MCRange | undefined;
    attributes?: Map<string, string>;

    constructor(name: string, depth: number) {
      this.tagName = name;
      this.depth = depth;
    }
  }

  /**
   * 计算指定 (lineNumber, columnNumber) 在多行文本中的绝对索引
   * @param lines - 文本的行数组
   * @param lineNumber - 行号（从 1 开始）
   * @param columnNumber - 列号（从 1 开始）
   * @returns 绝对索引（从 0 开始计数）
   */
  function positionToIndex(
    lines: string[],
    position: XmlPosition,
  ): number {
    const lineNumber = position.line;
    const columnNumber = position.column;

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

  function toRange(
    lines: string[],
    start: XmlPosition,
    end: XmlPosition
  ) {
    const startIndex = positionToIndex(lines, start);
    const endIndex = positionToIndex(lines, end);
    return new MCRange(startIndex, endIndex - startIndex);
  }
}