import { IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCMediaContent } from "./MCMediaContent";
import { fileIo } from "@kit.CoreFileKit";
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";

export class MCMediaContentWriter implements IMCMediaContentWriter {
  private mContent: MCMediaContent;
  private mFile?: fileIo.File | undefined = undefined;
  private mWriting = false;
  private mClosed = false;
  private mDataWrittenCallback?: (writer: MCMediaContentWriter, length: number) => void = undefined;
  private mClosedCallback?: (writer: MCMediaContentWriter) => void = undefined;

  constructor(content: MCMediaContent) {
    this.mContent = content;
  }

  get isClosed(): boolean {
    return this.mClosed;
  }

  on(event: 'dataWritten' | 'closed', callback: Function): void {
    switch (event) {
      case 'dataWritten':
        this.mDataWrittenCallback = callback as (writer: MCMediaContentWriter, length: number) => void;
        break;
      case 'closed':
        this.mClosedCallback = callback as (reader: MCMediaContentWriter) => void;
        break;
    }
  }

  off(event: 'dataWritten' | 'closed'): void {
    switch (event) {
      case 'dataWritten':
        this.mDataWrittenCallback = undefined;
        break;
      case 'closed':
        this.mClosedCallback = undefined;
        break;
    }
  }

  async writeData(data: ArrayBuffer, length: number): Promise<number> {
    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const filePath = this.mContent.filePath;

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Attempting to write ${length} bytes of data to file: ${filePath}.`);

    try {
      if (this.mWriting) {
        throw new Error(`Write operation already in progress. Concurrent operations are not allowed.`);
      }

      this.mWriting = true;

      if (data.byteLength < length) {
        throw new Error("Data length mismatch: provided data is smaller than expected length.");
      }

      // if (this.mDestroyed) { // 有 writer 并且未关闭时, content 不会被销毁;
      //   throw new Error("Content has been destroyed. Cannot write data.");
      // }

      if (this.mClosed) {
        throw new Error("Writer has been closed, cannot proceed with writing.");
      }

      if (!this.mFile) {
        this.mFile = await fileIo.open(filePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND | fileIo.OpenMode.CREATE);
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] File opened for writing at: ${filePath}.`);

        if (this.mClosed) {
          throw new Error("The writer was closed before the write operation could start.");
        }
      }

      const lengthWritten = await fileIo.write((this.mFile).fd, data, { length: length });
      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Successfully wrote ${lengthWritten} bytes to file: ${filePath}.`);
      if ( this.mDataWrittenCallback ) {
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Triggering 'dataWritten' callback with ${lengthWritten} bytes.`);
        this.mDataWrittenCallback(this, lengthWritten);
      }
      this.mWriting = false;
      return lengthWritten;
    }
    catch (error) {
      this.mWriting = false;
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Error during write: ${error.message}, stack: ${error.stack}.`);
      if    ( !this.mClosed ) {
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
      return;
    }

    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const filePath = this.mContent.filePath;

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Closing write operation for file: ${filePath}.`);

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

    if ( !this.mWriting && this.mClosedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Triggering closed callback for writer.`);
      this.mClosedCallback(this);
    }
  }
}