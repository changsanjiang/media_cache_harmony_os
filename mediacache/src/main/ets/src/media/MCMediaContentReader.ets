import { IMCMediaContentReader } from "../defines/IMCMediaContent";
import { fileIo, ReadOptions } from "@kit.CoreFileKit";
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";
import { MCMediaContent } from "./MCMediaContent";

export class MCMediaContentReader implements IMCMediaContentReader {
  readonly id: number;
  private mContent: MCMediaContent;
  private mFile?: fileIo.File | undefined = undefined;
  private mReading = false;
  private mClosed = false;
  private mClosedCallback?: (reader: MCMediaContentReader) => void = undefined;

  constructor(id: number, content: MCMediaContent) {
    this.id = id;
    this.mContent = content;
  }

  on(_: 'closed', callback: (reader: MCMediaContentReader) => void): void {
    this.mClosedCallback = callback;
  }

  off(_: 'closed'): void {
    this.mClosedCallback = undefined;
  }

  async readData(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const contentLength = this.mContent.length;
    const filePath = this.mContent.filePath;

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Attempting to read data at position ${position} with length ${length}.`);

    if (this.mReading) {
      throw new Error(`Read operation already in progress. Concurrent operations are not allowed.`);
    }

    this.mReading = true;
    try {
      if (buffer.byteLength === 0) {
        throw new Error("Buffer cannot be empty.");
      }

      // if (this.mContent.isDestroyed) { // 有 reader 并且未关闭时, content 不会被销毁;
      //   throw new Error("Content has been destroyed, cannot read data.");
      // }

      if (this.mClosed) {
        throw new Error("Reader has been closed, cannot proceed with reading.");
      }

      if (position < contentOffset || position >= contentOffset + contentLength) {
        throw new Error(`Position ${position} is out of valid range [${contentOffset}, ${contentOffset + contentLength}).`);
      }

      if (!this.mFile) {
        this.mFile = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.CREATE);
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] File opened for reading: ${filePath}.`);

        if (this.mClosed) {
          throw new Error("The reader was closed before the read operation could start.");
        }
      }

      const options: ReadOptions = {
        offset: position - contentOffset,
        length: Math.min(buffer.byteLength, length)
      };
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Reading file from position ${position} with options: ${JSON.stringify(options)}.`);

      const len = await fileIo.read(this.mFile.fd, buffer, options);
      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Successfully read ${len} bytes from position ${position}.`);
      this.mReading = false;
      return len;
    }
    catch (error) {
      this.mReading = false;
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Error during read: ${error.message}, stack: ${error.stack}.`);
      if      ( !this.mClosed ) {
        this.close();
      }
      else if ( this.mFile ) {
        this.closeFile();
      }
      throw error as Error;
    }
  }

  async close(): Promise<void> {
    if ( this.mClosed ) {
      // MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mContent.mediaId}, offset: ${this.mContent.contentOffset}] Reader is already closed. No action taken.`);
      return;
    }

    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const filePath = this.mContent.filePath;

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Closing read operation for file: ${filePath}.`);

    this.mClosed = true;

    return this.closeFile();
  }

  private async closeFile(): Promise<void> {
    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const filePath = this.mContent.filePath;

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Starting to close file: ${filePath}.`);

    if (this.mFile) {
      try {
        await fileIo.close(this.mFile);
        this.mFile = undefined;
        MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] File closed successfully: ${filePath}.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Failed to close file: ${filePath}. Error: ${error.message}.`);
      }
    }
    else {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] No file to close for: ${filePath}.`);
    }

    if ( !this.mReading && this.mClosedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Triggering closed callback for reader.`);
      this.mClosedCallback(this);
    }
  }
}