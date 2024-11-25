import { IMCMedia } from "../common/IMCMedia";
import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export class MCMediaFileContentLoader extends MCMediaContentLoader {
  private content: IMCMediaContent
  private loadRange: MCRange;

  // 传入之前请先对 content 做一次 readwriteRetain, loader 内部会在操作结束后执行对应的 readwriteRelease;
  constructor(media: IMCMedia, content: IMCMediaContent, loadRange: MCRange) {
    super(media);
    this.content = content;
    this.loadRange = loadRange;
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
    });
  }

  protected onClearBefore(): void {
    this.content.readwriteRelease();
  }
}