import { IMCMediaContent } from "../defines/IMCMediaContent";
import { IMCMediaContentNode } from "../defines/IMCMediaContentNode";
import { IMCStopFlag } from "../defines/IMCStopFlag";

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

  trimExcessContentsWithTest(predicate: (content: IMCMediaContent, stop: IMCStopFlag) => boolean): void {
    const stop: IMCStopFlag = { value: false };
    for (let i = this.mContents.length - 1; i >= 0; i--) {
      const content = this.mContents[i];
      const shouldRemove = predicate(content, stop);
      if ( shouldRemove ) {
        this.mContents.splice(i, 1);
      }
      if ( stop.value ) break;
    }
  }

  removeContent(content: IMCMediaContent): void {
    const index = this.mContents.indexOf(content);
    if (index >= 0) {
      this.mContents.splice(index, 1);
    }
  }
}