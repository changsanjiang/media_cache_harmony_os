import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";
import { fileIo } from '@kit.CoreFileKit';
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";

export class MCMediaContent extends MCReadwriteReference<MCMediaContent> implements IMCMediaContent {
  private mMediaId: string;
  private mLength = 0;
  private mFilePath: string;
  private mDestroyed = false;
  private mReader?: fileIo.File = undefined;
  private mWriter?: fileIo.File = undefined;
  private mDataWrittenCallbacks: Set<(content: IMCMediaContent, length: number) => void> = new Set();

  constructor(mediaId: string, contentOffset: number, filePath: string, length: number = 0) {
    super();
    this.mMediaId = mediaId;
    this.contentOffset = contentOffset;
    this.mFilePath = filePath;
    if (length > 0) {
      this.mLength = length;
    }

    MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}]: MCMediaContent instance created with length ${length}.`);
  }

  readonly contentOffset: number;

  get length(): Promise<number> {
    return this.mLock.lockAsync(() => this.mLength);
  }

  get lengthUnsafe(): number {
    return this.mLength;
  }

  get filePath(): string {
    return this.mFilePath;
  }

  readData(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    return this.mLock.lockAsync(async () => this.readDataUnsafe(position, buffer, length));
  }

  closeRead(): Promise<boolean> {
    return this.mLock.lockAsync(async () => this.closeReadUnsafe());
  }

  writeData(data: ArrayBuffer, length: number): Promise<number> {
    return this.mLock.lockAsync(async () => this.writeDataUnsafe(data, length));
  }

  closeWrite(): Promise<boolean> {
    return this.mLock.lockAsync(async () => this.closeWriteUnsafe());
  }

  // destroy(): Promise<boolean> {
  //   return this.mLock.lockAsync(async () => this.destroyUnsafe());
  // }

  on(_: "dataWritten", callback: (content: IMCMediaContent, length: number) => void): Promise<void> {
    return this.mLock.lockAsync(() => { this.mDataWrittenCallbacks.add(callback) });
  }

  off(_: "dataWritten", callback: (content: IMCMediaContent, length: number) => void): Promise<void> {
    return this.mLock.lockAsync(() => { this.mDataWrittenCallbacks.delete(callback) });
  }

  async readDataUnsafe(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to read data from position ${position} with length ${length}.`);

    try {
      if (buffer.byteLength === 0) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Buffer is empty. Read operation failed.`);
        throw new Error("Buffer cannot be empty.");
      }

      if (this.mDestroyed) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Content has been destroyed, cannot read data.`);
        throw new Error("Content has been destroyed, cannot read data.");
      }

      if (this.mReadwriteCount === 0) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Readwrite count is 0. Cannot read data.`);
        throw new Error("Please retain a readwrite count before reading data.");
      }

      if (position < this.contentOffset || position >= this.contentOffset + this.mLength) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Position out of range: position ${position}, content length ${this.mLength}.`);
        throw new Error("Position is out of content range.");
      }

      if (!this.mReader) {
        this.mReader = await fileIo.open(this.mFilePath, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.CREATE);
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Reader created.`);
      }

      const len = await fileIo.read(this.mReader.fd, buffer, { offset: position - this.contentOffset, length: Math.min(buffer.byteLength, length) });
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Read data successful: ${len} bytes.`);
      return len;
    } catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error during read: ${error.message}`);
      throw error as Error;
    }
  }

  async closeReadUnsafe(): Promise<boolean> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to close read operation.`);

    if (this.mReadwriteCount > 0) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Cannot close read operation. Readwrite count is greater than 0.`);
      return false;
    }

    try {
      if (this.mReader != undefined) {
        await fileIo.close(this.mReader);
        this.mReader = undefined;
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Reader closed.`);
      }
      return true;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error closing read operation: ${error.message}`);
      throw error as Error;
    }
  }

  async writeDataUnsafe(data: ArrayBuffer, length: number): Promise<number> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to write data of length ${length}.`);

    try {
      if (data.byteLength < length) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Data length mismatch. Cannot write data.`);
        throw new Error("Data length mismatch.");
      }

      if (this.mDestroyed) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Content has been destroyed. Cannot write data.`);
        throw new Error("Content has been destroyed. Cannot write data.");
      }

      if (this.mReadwriteCount === 0) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Readwrite count is 0. Cannot write data.`);
        throw new Error("Please retain a readwrite count before writing data.");
      }

      if (this.mWriter == undefined) {
        this.mWriter = await fileIo.open(this.mFilePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND | fileIo.OpenMode.CREATE);
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Writer created.`);
      }

      const lengthWritten = await fileIo.write(this.mWriter.fd, data, { length: length });
      this.mLength += lengthWritten;
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Successfully wrote data: ${lengthWritten} bytes.`);

      Promise.resolve(this.mDataWrittenCallbacks.values()).then((callbacks) => {
        for (let callback of callbacks) {
          callback(this, lengthWritten);
        }
      });

      return lengthWritten;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error during write: ${error.message}`);
      throw error as Error;
    }
  }

  async closeWriteUnsafe(): Promise<boolean> {
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to close write operation.`);

    if (this.mReadwriteCount > 0) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Cannot close write operation. Readwrite count is greater than 0.`);
      return false;
    }

    try {
      if (this.mWriter != undefined) {
        await fileIo.close(this.mWriter);
        this.mWriter = undefined;
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Writer closed.`);
      }
      return true;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error closing write operation: ${error.message}`);
      throw error as Error;
    }
  }

  async destroyUnsafe(): Promise<boolean> {
    MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Attempting to destroy content.`);

    if (this.mDestroyed) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Content already destroyed.`);
      return true;
    }

    if (this.mReadwriteCount > 0) {
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Cannot destroy content. Readwrite count is greater than 0.`);
      return false;
    }

    try {
      if (this.mReader != undefined) {
        await fileIo.close(this.mReader);
        this.mReader = undefined;
      }
      if (this.mWriter != undefined) {
        await fileIo.close(this.mWriter);
        this.mWriter = undefined;
      }
      try { await fileIo.unlink(this.mFilePath); } catch (e) { }
      this.mDestroyed = true;

      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Content destroyed successfully.`);
      return true;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mMediaId}, offset: ${this.contentOffset}] Error during destruction: ${error.message}`);
      throw error as Error;
    }
  }
}