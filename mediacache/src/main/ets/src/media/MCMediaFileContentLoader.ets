import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export class MCMediaFileContentLoader extends MCMediaContentLoader {
  private content: IMCMediaContent
  private loadRange: MCRange;

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

    this.onContentReady(this.content, this.loadRange);
  }
}