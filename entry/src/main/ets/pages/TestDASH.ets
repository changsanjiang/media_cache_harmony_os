import FileMgr from '../utils/FileMgr'
import { xml, util, convertxml } from '@kit.ArkTS'; // 需要使用util模块函数对文件编码
import { fileIo } from '@kit.CoreFileKit';

let str: string = '';

function tagFunc(name: string, value: string): boolean {
  str = name + value;
  console.error('tag-' + str);
  return true;
}

function attFunc(name: string, value: string): boolean {
  str = name + ' ' + value;
  console.error('attri-' + str);
  return true;
}

function tokenFunc(name: xml.EventType, value: xml.ParseInfo): boolean {
  str = name + ' ' + value.getDepth();
  console.error('token-' + str);
  return true;
}

@Entry
@Component
struct TestDASH {
  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this);
    const path = `${ctx.filesDir}/test.mpd`;
    await FileMgr.copyRawFileToPath(ctx, "test.mpd", path, { returnIfExists: true });
    this.convertXml(path);
  }

  async convertXml(path: string): Promise<void> {
    let options: convertxml.ConvertOptions = {
      // trim: false 转换后是否删除文本前后的空格，否
      // declarationKey: "_declaration" 转换后文件声明使用_declaration来标识
      // instructionKey: "_instruction" 转换后指令使用_instruction标识
      // attributesKey: "_attributes" 转换后属性使用_attributes标识
      // textKey: "_text" 转换后标签值使用_text标识
      // cdataKey: "_cdata" 转换后未解析数据使用_cdata标识
      // docTypeKey: "_doctype" 转换后文档类型使用_doctype标识
      // commentKey: "_comment" 转换后注释使用_comment标识
      // parentKey: "_parent" 转换后父类使用_parent标识
      // typeKey: "_type" 转换后元素类型使用_type标识
      // nameKey: "_name" 转换后标签名称使用_name标识
      // elementsKey: "_elements" 转换后元素使用_elements标识
      trim: false,
      declarationKey: "_declaration",
      instructionKey: "_instruction",
      attributesKey: "_attributes",
      textKey: "_text",
      cdataKey: "_cdata",
      doctypeKey: "_doctype",
      commentKey: "_comment",
      parentKey: "_parent",
      typeKey: "_type",
      nameKey: "_name",
      elementsKey: "_elements"
    }
    const xml = await fileIo.readText(path);
    let conv: convertxml.ConvertXML = new convertxml.ConvertXML();
    let result: object = conv.convertToJSObject(xml, options);
    let strRes: string = JSON.stringify(result); // 将js对象转换为json字符串，用于显式输出
    console.error(strRes);
  }

  async parse(path: string): Promise<void> {
    const strXml = await fileIo.readText(path);
    let textEncoder: util.TextEncoder = new util.TextEncoder();
    let arrBuffer: Uint8Array = textEncoder.encodeInto(strXml);
    let that: xml.XmlPullParser = new xml.XmlPullParser(arrBuffer.buffer as object as ArrayBuffer, 'UTF-8');

    let options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,
      tagValueCallbackFunction: tagFunc,
      attributeValueCallbackFunction: attFunc,
      tokenValueCallbackFunction: tokenFunc
    };
    that.parse(options);
  }


  build() {
    Column() {
      Text("DASH")
        .id('DASH')
        .fontSize(50)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
    }
  }
}