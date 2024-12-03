import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export class MCMediaFileContentLoader extends MCMediaContentLoader {
  private content: IMCMediaContent
  private loadRange: MCRange;

  // 传入之前请先对 content 做一次 readwriteRetain, loader 内部会在操作结束后执行对应的 readwriteRelease;
  constructor(content: IMCMediaContent, loadRange: MCRange) {
    super();
    this.content = content;
    this.loadRange = loadRange;
  }

  protected async onPrepare(): Promise<void> {
    const start = this.loadRange.location;
    const end = this.loadRange.max;
    const contentStart = this.content.contentOffset;
    const contentEnd = this.content.contentOffset + this.content.length;

    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Preparing MCMediaFileContentLoader with range [${start}, ${end}) and content range [${contentStart}, ${contentEnd}).`);

    if (start < contentStart || end > contentEnd) {
      throw new Error(`Load range [${start}, ${end}) is out of bounds for content range [${contentStart}, ${contentEnd}).`);;
    }

    this.contentReady(this.content.readwriteRetain(), this.loadRange);
  }

  protected onClearBefore(): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Releasing retained content in MCMediaFileContentLoader.');
    this.content.readwriteRelease();
  }
}