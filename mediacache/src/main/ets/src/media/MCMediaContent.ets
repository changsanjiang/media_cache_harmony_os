import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";
import { fileIo, ReadOptions } from '@kit.CoreFileKit';
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";

export class MCMediaContent extends MCReadwriteReference<MCMediaContent> implements IMCMediaContent {
  private mMediaId: string;
  private mLength = 0;
  private mFilePath: string;
  private mDestroyed = false;
  private mReader?: Promise<fileIo.File> | undefined = undefined;
  private mWriter?: Promise<fileIo.File> | undefined = undefined;
  private mDataWrittenCallback: ((content: IMCMediaContent, length: number) => void) | undefined = undefined;
  private mTemp = false; // 是否是临时内容

  /// mediaId: 媒体id;
  /// contentOffset: 内容在媒体中的偏移量;
  /// filePath: 内容文件路径;
  /// length: 文件大小;
  /// isTemp: 是否是临时内容;
  constructor(mediaId: string, contentOffset: number, filePath: string, length: number = 0, isTemp: boolean = false) {
    super();
    this.mMediaId = mediaId;
    this.contentOffset = contentOffset;
    this.mFilePath = filePath;
    this.mTemp = isTemp;
    if (length > 0) {
      this.mLength = length;
    }

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Instance created: {
      "filePath": "${this.mFilePath}",
      "length": ${this.mLength || 0},
      "isTemp": ${this.mTemp}
    }`);
  }

  readonly contentOffset: number;

  get length(): number {
    return this.mLength;
  }

  get filePath(): string {
    return this.mFilePath;
  }

  get isTemp(): boolean {
    return this.mTemp;
  }

  async readData(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to read data from position ${position} with length ${length}.`);

    try {
      if (buffer.byteLength === 0) {
        throw new Error("Buffer cannot be empty.");
      }

      if (this.mDestroyed) {
        throw new Error("Content has been destroyed, cannot read data.");
      }

      if (this.mReadwriteCount === 0) {
        throw new Error("Please retain a readwrite count before reading data.");
      }

      if (position < this.contentOffset || position >= this.contentOffset + this.mLength) {
        throw new Error(`Position is out of content range: position ${position}, valid range [${this.contentOffset}, ${this.contentOffset + this.mLength}).`);
      }

      if (!this.mReader) {
        this.mReader = fileIo.open(this.mFilePath, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.CREATE);
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Reader created for file: ${this.mFilePath}.`);
      }

      const options: ReadOptions = {
        offset: position - this.contentOffset,
        length: Math.min(buffer.byteLength, length)
      };
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Reading file with options: ${JSON.stringify(options)} }.`);

      const len = await fileIo.read((await this.mReader).fd, buffer, options);
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Read successful: ${len} bytes from file ${this.mFilePath}.`);

      return len;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error during read: ${error.message}, stack: ${error.stack}.`);
      throw error as Error;
    }
  }

  async closeRead(): Promise<boolean> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to close read operation for file: ${this.mFilePath}.`);

    if (this.mReadwriteCount > 0) {
      MCLogger.warn(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Cannot close read operation. Readwrite count is ${this.mReadwriteCount}.`);
      return false;
    }

    if (this.mReader) {
      const reader = this.mReader;
      this.mReader = undefined;

      try {
        await fileIo.close(await reader);
        MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Reader closed successfully for file: ${this.mFilePath}.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Failed to close reader for file: ${this.mFilePath}. Error: ${error.message}.`);
        return false;
      }
    }
    else {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] No active reader to close for file: ${this.mFilePath}.`);
    }
    return true;
  }

  async writeData(data: ArrayBuffer, length: number): Promise<number> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to write data of length ${length} to file: ${this.mFilePath}.`);

    try {
      if (data.byteLength < length) {
        throw new Error("Data length mismatch.");
      }

      if (this.mDestroyed) {
        throw new Error("Content has been destroyed. Cannot write data.");
      }

      if (this.mReadwriteCount === 0) {
        throw new Error("Readwrite count is 0. Cannot write data.");
      }

      if (!this.mWriter) {
        this.mWriter = fileIo.open(this.mFilePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND | fileIo.OpenMode.CREATE);
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Writer created for file: ${this.mFilePath}.`);
      }

      const lengthWritten = await fileIo.write((await this.mWriter).fd, data, { length: length });
      this.mLength += lengthWritten;
      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Successfully wrote ${lengthWritten} bytes to file: ${this.mFilePath}. Total length: ${this.mLength}.`);

      this.dataWritten(lengthWritten);

      return lengthWritten;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error during write: ${error.message}, stack: ${error.stack}.`);
      throw error as Error;
    }
  }

  private async dataWritten(length: number): Promise<void> {
    if (this.mDataWrittenCallback) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Executing dataWritten callback with length: ${length}.`);
      this.mDataWrittenCallback(this, length);
    }
    else {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] No dataWritten callback to execute.`);
    }
  }

  async closeWrite(): Promise<boolean> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to close write operation for file: ${this.mFilePath}.`);

    if (this.mReadwriteCount > 0) {
      MCLogger.warn(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Cannot close write operation. Readwrite count is ${this.mReadwriteCount}.`);
      return false;
    }

    if (this.mWriter) {
      const writer = this.mWriter;
      this.mWriter = undefined;

      try {
        await fileIo.close(await writer);
        MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Writer closed successfully for file: ${this.mFilePath}.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Failed to close writer for file: ${this.mFilePath}. Error: ${error.message}.`);
        return false;
      }
    }
    else {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] No active writer to close for file: ${this.mFilePath}.`);
    }
    return true;
  }

  async destroy(): Promise<boolean> {
    MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to destroy content.`);

    if (this.mDestroyed) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Content already destroyed.`);
      return true;
    }

    if (this.mReadwriteCount > 0) {
      MCLogger.warn(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Cannot destroy content. Readwrite count is ${this.mReadwriteCount}.`);
      return false;
    }

    this.mDestroyed = true;

    try {
      await this.closeRead();
      await this.closeWrite();

      try { await fileIo.unlink(this.mFilePath); } catch (e) { }

      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Content destroyed successfully.`);
      return true;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error during destruction: ${error.message}, stack: ${error.stack}.`);
      throw error as Error;
    }
  }

  on(_: "dataWritten", callback: (content: IMCMediaContent, length: number) => void): void {
    this.mDataWrittenCallback = callback;
  }

  off(_: "dataWritten"): void {
    this.mDataWrittenCallback = undefined;
  }

  protected getInstance(): MCMediaContent {
    return this;
  }
}