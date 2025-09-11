import { util, xml } from '@kit.ArkTS';
import { DashXmlNode } from '../../defines/DashDefines';
import { _DashXmlNode } from './DashModel';

export namespace XmlParser {
  export const xmlDeclaration = '<?xml version="1.0" encoding="utf-8"?>';

  /** 解析结果 */
  export interface XmlParseResult {
    /** 压缩后的 XML 文本 */
    compactXml: string;
    /** 根节点 */
    rootNode: DashXmlNode;
  }

  /**
   * 解析 mpd XML 文本，删除缩进换行并压缩为紧凑格式，
   * 同时生成节点树。
   *
   * @param rawXml 原始 XML 文本
   * @returns {XmlParseResult} 包含压缩后的 XML 字符串和根节点树
   */
  export function parse(rawXml: string): XmlParseResult {
    const textEncoder = new util.TextEncoder();
    const data = textEncoder.encodeInto(rawXml);
    const parser = new xml.XmlPullParser(data.buffer as object as ArrayBuffer);

    let compactXml = xmlDeclaration;
    let openTagPending = false;         // 标记是否有未闭合的 start tag

    const rootNode = new _DashXmlNode("");  // 根节点占位
    const stack: _DashXmlNode[] = [rootNode];

    const options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,

      /** 处理属性 */
      attributeValueCallbackFunction: (key, value) => {
        compactXml += ` ${key}="${value}"`;

        const element = stack[stack.length - 1];
        element.addAttribute(key, value);
        return true;
      },

      /** 处理元素和文本节点 */
      tokenValueCallbackFunction: (key, value) => {
        switch (key) {
          case xml.EventType.START_TAG: {
            // 创建新节点，加入父节点的 children
            const node = new _DashXmlNode(value.getName());
            const parent = stack[stack.length - 1]; // 将新节点加入栈顶父节点的 children
            parent.children.push(node);
            stack.push(node); // 当前节点入栈

            // 记录节点起点位置
            node.nodeStartIndex = compactXml.length;

            const tagName = value.getName();
            compactXml += `<${tagName}`; // 先不补 >，等看看有没有属性或 TEXT
            openTagPending = true; // 记录 start tag 打开
            break;
          }
          case xml.EventType.END_TAG: {
            const tagName = value.getName();
            const element = stack.pop()!; // 弹出栈顶节点

            if ( openTagPending ) {
              // 空节点 <tag ... />
              compactXml += "/>"; // 没有子节点，直接补 />
              openTagPending = false;
              element.startTagEndIndex = compactXml.length - element.nodeStartIndex;
            }
            else {
              // 普通闭合标签 </tag>
              compactXml += `</${tagName}>`;
            }

            element.length = compactXml.length - element.nodeStartIndex; // 设置节点长度
            break;
          }
          case xml.EventType.TEXT: {
            const parent = stack[stack.length - 1];

            if (openTagPending) {
              // 补全 start tag 的 >
              compactXml += ">";
              openTagPending = false;
              parent.startTagEndIndex = compactXml.length - parent.nodeStartIndex;
            }

            // 压缩文本：合并多余空白为单个空格，再 trim
            const innerText = value.getText().trim()
            if ( innerText.length > 0 ) {
              parent.innerText = innerText;
              parent.innerTextStartIndex = compactXml.length - parent.nodeStartIndex;
              compactXml += innerText;
            }
            break;
          }
          default: break;
        }
        return true;
      }
    };
    parser.parseXml(options);

    // mpd 文档必须只有一个根节点
    if (rootNode.children.length !== 1) {
      throw new Error("Invalid XML: document must have exactly one root element.");
    }

    return {
      compactXml,
      rootNode: rootNode.children[0] // 返回真正的根节点
    };
  }

  /**
   * 查找第一层（parent.children）中所有匹配 tagName 的节点
   * @param parent 父节点
   * @param tagName 标签名
   */
  export function findDirectChildrenByTagName(
    parent: DashXmlNode,
    tagName: string
  ): DashXmlNode[] {
    return parent.children.filter(node => node.tagName === tagName);
  }

  /**
   * 计算 descendant 节点在整个 XML 文本中的绝对起始索引
   * @param root 根节点
   * @param descendant 目标节点
   * @returns 起始索引，未找到则返回 -1
   */
  export function computeStartIndex(
    root: DashXmlNode,
    descendant: DashXmlNode,
  ): number {
    return computeStartIndexRecursive(root, descendant, xmlDeclaration.length);
  }

  /** DFS, Depth-First Search
   - 树结构:
     A
     ├─ B
     │  ├─ D
     │  └─ E
     └─ C

   - 遍历顺序:
     A → B → D → E → C
   */
  function computeStartIndexRecursive(node: DashXmlNode, descendant: DashXmlNode, baseIndex: number): number {
    if ( node === descendant ) {
      return baseIndex;
    }

    let offset = baseIndex + node.startTagEndIndex; // 子节点起点从父 startTagRange 后开始
    for ( const child of node.children ) {
      const startIndex = computeStartIndexRecursive(child, descendant, offset);
      if ( startIndex != -1 ) {
        return startIndex;
      }
      offset += child.length;
    }
    return -1;
  }
}