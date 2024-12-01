import { IMCMediaContent } from "../defines/IMCMediaContent";
import { IMCMediaContentNode } from "../defines/IMCMediaContentNode";

export class MCMediaContentNode implements IMCMediaContentNode {
  private mContents: Array<IMCMediaContent> = new Array();

  constructor(placement: number) {
    this.placement = placement;
  }

  readonly placement: number;

  prev?: MCMediaContentNode = undefined;
  next?: MCMediaContentNode = undefined;

  get numberOfContents(): number {
    return this.mContents.length;
  }

  get longestContent(): IMCMediaContent | undefined {
    let retv: IMCMediaContent | undefined = undefined;
    for (let content of this.mContents) {
      if (retv === undefined || content.length > retv.length) {
        retv = content;
      }
    }
    return retv;
  }

  addContent(content: IMCMediaContent) {
    this.mContents.push(content);
  }

  filterContents(predicate: (content: IMCMediaContent) => boolean): IMCMediaContent[] {
    return this.mContents.filter(predicate);
  }

  removeContent(content: IMCMediaContent): boolean {
    const index = this.mContents.indexOf(content);
    if (index >= 0) {
      this.mContents.splice(index, 1);
      return true;
    }
    return false;
  }
}