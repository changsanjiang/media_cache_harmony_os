import { XmlParser } from "../../../../../../Index";
import { DashElement, DashXmlNode } from "../../defines/DashDefines";

export class _DashXmlNode implements DashXmlNode {
  tagName: string;
  attributes?: Map<string, string>;
  children: _DashXmlNode[] = [];
  innerText?: string | undefined;
  startTagEndIndex: number = 0;  // 相对于node自身的位置;
  innerTextStartIndex: number = 0; // 相对于node自身的位置;
  length: number = 0;

  nodeStartIndex: number = 0; // 节点绝对起点位置;

  constructor(name: string) {
    this.tagName = name;
  }

  addAttribute(key: string, value: string) {
    if ( this.attributes == undefined ) {
      this.attributes = new Map();
    }
    this.attributes.set(key, value);
  }
}

export class _DashElement implements DashElement.Element {
  node: DashXmlNode;

  constructor(node: DashXmlNode) {
    this.node = node;
  }
}

export class _MPD extends _DashElement implements DashElement.MPD {
  readonly eBaseURLs?: readonly DashElement.BaseURL[] | undefined;
  readonly ePeriods?: readonly DashElement.Period[] | undefined;

  constructor(node: DashXmlNode) {
    super(node);

    this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
    this.ePeriods = XmlParser.findDirectChildrenByTagName(node, "Period").map(it => new _Period(it));
  }
}

export class _Period extends _DashElement implements DashElement.Period {
  readonly eBaseURLs?: readonly _BaseURL[];
  readonly eAdaptationSets?: readonly _AdaptationSet[] | undefined;

  constructor(node: DashXmlNode) {
    super(node);

    this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
    this.eAdaptationSets = XmlParser.findDirectChildrenByTagName(node, "AdaptationSet").map(it => new _AdaptationSet(it));
  }
}

export class _AdaptationSet extends _DashElement implements DashElement.AdaptationSet {
  readonly eBaseURLs?: readonly _BaseURL[] | undefined;
  eRepresentations?: readonly _Representation[];

  constructor(node: DashXmlNode) {
    super(node);

    this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
    this.eRepresentations = XmlParser.findDirectChildrenByTagName(node, "Representation").map(it => new _Representation(it));
  }
}

export class _Representation extends _DashElement implements DashElement.Representation {
  readonly eBaseURLs?: readonly _BaseURL[] | undefined;
  readonly eSegmentTemplate?: _SegmentTemplate;

  constructor(node: DashXmlNode) {
    super(node);

    this.eBaseURLs = XmlParser.findDirectChildrenByTagName(node, "BaseURL").map(it => new _BaseURL(it));
    this.eSegmentTemplate = getFirstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "SegmentTemplate").map(it => new _SegmentTemplate(it)));
  }
}

export class _SegmentBase extends _DashElement implements DashElement.SegmentBase {
  readonly eInitialization?: _URLType;
  readonly eRepresentationIndex?: _URLType;

  constructor(node: DashXmlNode) {
    super(node);

    this.eInitialization = getFirstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "Initialization").map(it => new _URLType(it)));
    this.eRepresentationIndex = getFirstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "RepresentationIndex").map(it => new _URLType(it)));
  }
}

export class _MultipleSegmentBase extends _SegmentBase implements DashElement.MultipleSegmentBase {
  readonly eSegmentTimeline?: _SegmentTimeline;
  readonly aStartNumber?: number;

  constructor(node: DashXmlNode) {
    super(node);

    this.aStartNumber = toInt(node.attributes?.get("startNumber"));
    this.eSegmentTimeline = getFirstOrUndefined(XmlParser.findDirectChildrenByTagName(node, "SegmentTimeline").map(it => new _SegmentTimeline(it)));
  }
}

export class _SegmentTemplate extends _MultipleSegmentBase implements DashElement.SegmentTemplate {
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

export class _SegmentTimeline extends _DashElement implements DashElement.SegmentTimeline {
  readonly eSs: readonly _S[];

  constructor(node: DashXmlNode) {
    super(node);

    this.eSs = XmlParser.findDirectChildrenByTagName(node, "S").map(it => new _S(it));
  }
}

export class _S extends _DashElement implements DashElement.S {

}

export class _BaseURL extends _DashElement implements DashElement.BaseURL {
  value: string;
  aByteRange?: string | undefined;

  constructor(node: DashXmlNode) {
    super(node);
    this.value = node.innerText!;
  }
}

export class _URLType extends _DashElement implements DashElement.URLType {
  aSourceURL?: DashElement.AnyURI;
  aRange?: string;
}


function toInt(valueStr?: string): number | undefined {
  const str = valueStr?.trim();
  return str ? parseInt(str) : undefined;
}

function getFirstOrUndefined<T>(arr: T[]): T | undefined {
  return arr.length > 0 ? arr[0] : undefined;
}