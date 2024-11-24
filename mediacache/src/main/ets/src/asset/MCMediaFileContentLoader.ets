import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export class MCMediaFileContentLoader extends MCMediaContentLoader {
  private content: IMCMediaContent
  private loadRange: MCRange;

  constructor(content: IMCMediaContent, loadRange: MCRange) {
    super();
    this.content = content;
    this.loadRange = loadRange;
    this.content.readwriteRetain();
  }

  protected onPrepare(): Promise<void> {
    return new Promise<void>(async (resolve, reject) => {
      const start = this.loadRange.location;
      const end = this.loadRange.max;
      const contentStart = this.content.contentOffset;
      const contentEnd = this.content.contentOffset + await this.content.length;
      if (start < contentStart || end > contentEnd) {
        reject(new Error(`Load range [${start}, ${end}) is out of bounds for content range [${contentStart}, ${contentEnd}).`));
        return;
      }
      this.content.readwriteRetain();
      this.contentReady(this.content, this.loadRange);
      resolve();
    })
  }

  protected onClearBefore(): void {
    this.content.readwriteRelease();
  }
}