import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export class MCMediaFileContentLoader extends MCMediaContentLoader {
  private content: IMCMediaContent
  private readRange: MCRange;

  constructor(content: IMCMediaContent, readRange: MCRange) {
    super();
    this.content = content;
    this.readRange = readRange;
  }

  async prepare(): Promise<void> {
    const readStart = this.readRange.location;
    const readEnd = this.readRange.max;
    const contentStart = this.content.contentOffset;
    const contentEnd = this.content.contentOffset + this.content.length;

    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[File] Preparing loader with range [${readStart}, ${readEnd}) and content range [${contentStart}, ${contentEnd}).`);

    if (readStart < contentStart || readEnd > contentEnd) {
      this.onError(new Error(`Read range [${readStart}, ${readEnd}) is out of bounds for content range [${contentStart}, ${contentEnd}).`));
      return;
    }

    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[File] Read range is valid. Invoking onPrepared.`);
    this.onPrepared(this.content, this.readRange);
  }
}