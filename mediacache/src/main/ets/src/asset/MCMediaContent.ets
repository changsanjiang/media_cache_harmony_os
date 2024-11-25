import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";
import { fileIo } from '@kit.CoreFileKit';

export class MCMediaContent extends MCReadwriteReference<MCMediaContent> implements IMCMediaContent {
  private mLength = 0;
  private mFilePath: string;
  private mDestroyed = false;
  private mReader?: fileIo.File = undefined;
  private mWriter?: fileIo.File = undefined;
  private mDataWrittenCallbacks: Set<(content: IMCMediaContent, length: number) => void> = new Set();

  constructor(contentOffset: number, filePath: string, length: number = 0) {
    super();
    this.contentOffset = contentOffset;
    this.mFilePath = filePath;
    if ( length != 0 ) this.mLength = length;
  }

  readonly contentOffset: number;

  get length(): Promise<number> {
    return this.mLock.lockAsync(() => this.mLength);
  }

  get unsafeLength(): number {
    return this.mLength;
  }

  get filePath(): string {
    return this.mFilePath;
  }

  readData(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    if (buffer.byteLength === 0) {
      throw new Error("Buffer cannot be empty.");
    }
    return this.mLock.lockAsync(async () => {
      if (this.mDestroyed) {
        throw new Error("Content has been destroyed, cannot read data.");
      }

      if (this.mReadwriteCount === 0) {
        throw new Error("Please retain a readwrite count before reading data.");
      }

      if (position < this.contentOffset || position >= this.contentOffset + this.mLength) {
        throw new Error("Position is out of content range.");
      }

      if ( this.mReader == undefined ) {
        this.mReader = await fileIo.open(this.mFilePath, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.CREATE);
      }

      return fileIo.read(this.mReader.fd, buffer, { offset: position - this.contentOffset, length: length });
    });
  }

  closeRead(): Promise<boolean> {
    return this.mLock.lockAsync(async () => {
      if ( this.mReadwriteCount > 0 ) {
        return false;
      }
      if ( this.mReader != undefined ) {
        await fileIo.close(this.mReader);
        this.mReader = undefined;
      }
      return true;
    });
  }

  writeData(data: ArrayBuffer, length: number): Promise<number> {
    return this.mLock.lockAsync(async () => {
      if ( this.mDestroyed ) {
        throw new Error("内容已被销毁, 无法再写入数据了");
      }
      if ( this.mReadwriteCount === 0 ) {
        throw new Error("写入数据之前请增加一次读写计数");
      }

      if ( this.mWriter == undefined ) {
        this.mWriter = await fileIo.open(this.mFilePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND | fileIo.OpenMode.CREATE);
      }
      const lengthWritten = await fileIo.write(this.mWriter.fd, data, { length: length });
      this.mLength += lengthWritten;
      return lengthWritten;
    }).then((lengthWritten) => {
      this.mDataWrittenCallbacks.forEach((callback) => callback(this, lengthWritten));
      return lengthWritten;
    });
  }

  closeWrite(): Promise<boolean> {
    return this.mLock.lockAsync(async () => {
      if ( this.mReadwriteCount > 0 ) {
        return false;
      }
      if ( this.mWriter != undefined ) {
        await fileIo.close(this.mWriter);
        this.mWriter = undefined;
      }
      return true;
    });
  }

  destroy(): Promise<boolean> {
    return this.mLock.lockAsync(async () => {
      if ( this.mDestroyed ) {
        return true;
      }

      if ( this.mReadwriteCount > 0 ) {
        return false;
      }

      if ( this.mReader != undefined ) {
        await fileIo.close(this.mReader);
        this.mReader = undefined;
      }
      if ( this.mWriter != undefined ) {
        await fileIo.close(this.mWriter);
        this.mWriter = undefined;
      }
      try { await fileIo.unlink(this.mFilePath); } catch (e) { }
      this.mDestroyed = true;
      return true;
    });
  }

  on(_: "dataWritten", callback: (content: IMCMediaContent, length: number) => void): Promise<void> {
    return this.mLock.lockAsync(() => { this.mDataWrittenCallbacks.add(callback) });
  }

  off(_: "dataWritten", callback: (content: IMCMediaContent, length: number) => void): Promise<void> {
    return this.mLock.lockAsync(() => { this.mDataWrittenCallbacks.delete(callback) });
  }
}