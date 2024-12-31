import { IMCMediaContentReader } from "../defines/IMCMediaContent";
import { fileIo, ReadOptions } from "@kit.CoreFileKit";
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";
import { MCMediaContent } from "./MCMediaContent";
import { MCAbortSignal } from "../utils/MCAbortController";

export class MCMediaContentReader implements IMCMediaContentReader {
  private mContent: MCMediaContent;
  private mAbortSignal: MCAbortSignal
  private mFile?: fileIo.File | undefined = undefined;
  private mReading = false;
  private mClosed = false;
  private mAbortedCallback = () => this.close();

  constructor(content: MCMediaContent, abortSignal: MCAbortSignal) {
    this.mContent = content;
    this.mAbortSignal = abortSignal;
    abortSignal.addEventListener('aborted', this.mAbortedCallback);
  }

  get isClosed(): boolean {
    return this.mClosed;
  }

  async readData(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const contentLength = this.mContent.length;
    const filePath = this.mContent.filePath;

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Attempting to read data at position ${position} with length ${length}.`);

    try {
      if (this.mReading) {
        throw new Error(`Read operation already in progress. Concurrent operations are not allowed.`);
      }

      this.mReading = true;

      if (buffer.byteLength === 0) {
        throw new Error("Buffer cannot be empty.");
      }

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
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Error during read: ${error.message}, Stack trace: ${error.stack}.`);
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
    const file = this.mFile;
    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const filePath = this.mContent.filePath;
    this.mAbortSignal.removeEventListener('aborted', this.mAbortedCallback);

    if ( file ) {
      this.mFile = undefined;
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Starting to close file: ${filePath}.`);

      try {
        await fileIo.close(file);
        MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] File closed successfully: ${filePath}.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Failed to close file: ${filePath}. Error: ${error.message}.`);
      }
    }
    else {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] No file to close for: ${filePath}.`);
    }
  }
}