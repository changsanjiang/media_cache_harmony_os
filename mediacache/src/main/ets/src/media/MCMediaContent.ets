import { IMCMediaContent, IMCMediaContentReader, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCMediaContentReader } from "./MCMediaContentReader";
import { MCMediaContentWriter } from "./MCMediaContentWriter";
import { fileIo } from "@kit.CoreFileKit";

export class MCMediaContent implements IMCMediaContent {
  private mLength = 0;
  private mDestroyed = false;
  private mNextReaderId = 0;
  private mReaders?: Map<number, MCMediaContentReader> = undefined;
  private mWriter?: MCMediaContentWriter = undefined;
  private mDataWrittenCallback?: (content: IMCMediaContent) => void = undefined;
  private mTemp = false; // 是否是临时内容
  private mReadPromiseLink?: Promise<void> = undefined;
  private mWritePromise?: Promise<void> = undefined;

  /// mediaId: 媒体id;
  /// contentOffset: 内容在媒体中的偏移量;
  /// filePath: 内容文件路径;
  /// length: 文件大小;
  /// isTemp: 是否是临时内容;
  constructor(mediaId: string, contentOffset: number, filePath: string, length: number = 0, isTemp: boolean = false) {
    this.mediaId = mediaId;
    this.contentOffset = contentOffset;
    this.filePath = filePath;
    this.mTemp = isTemp;
    if (length > 0) {
      this.mLength = length;
    }

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Instance created: {
      "filePath": "${this.filePath}",
      "length": ${this.mLength || 0},
      "isTemp": ${this.mTemp}
    }`);
  }

  readonly mediaId: string;
  readonly contentOffset: number;
  readonly filePath: string;

  get length(): number {
    return this.mLength;
  }

  get isTemp(): boolean {
    return this.mTemp;
  }

  get isDestroyed(): boolean {
    return this.mDestroyed;
  }

  createReader(): IMCMediaContentReader {
    if ( this.mDestroyed ) {
      throw new Error("Content has been destroyed, cannot create reader.");
    }

    if ( this.mReaders === undefined ) {
      this.mReaders = new Map();
    }
    const id = this.mNextReaderId;
    const reader = new MCMediaContentReader(id, this);
    this.mNextReaderId += 1;
    this.mReaders.set(id, reader);
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Reader created ${id} for content.`);

    const promise = new Promise<void>((resolve) => {
      reader.on('closed', (reader) => {
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Reader closed ${id} for content.`);

        this.mReaders?.delete(id);
        if ( this.mReaders?.size === 0 ) {
          this.mReadPromiseLink = undefined;
        }
        reader.off('closed');
        resolve();
      });
    });
    this.mReadPromiseLink = this.mReadPromiseLink ? this.mReadPromiseLink.then(() => promise) : promise; // 创建读取链, 确保读取期间不被 destroy;
    return reader;
  }

  createWriter(): IMCMediaContentWriter {
    if ( this.mDestroyed ) {
      throw new Error("Content has been destroyed, cannot create writer.");
    }

    if ( this.mWriter && !this.mWriter.isClosed ) {
      throw new Error("Only one writer can be created."); // 只允许创建一个writer写入数据, 不能创建多个writer写入数据;
    }

    const writer = new MCMediaContentWriter(this);
    this.mWriter = writer;
    writer.on('dataWritten', (_: MCMediaContentWriter, length: number) => {
      this.mLength += length;
      this.onDataWritten();
    });

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Writer created for content.`);

    this.mWritePromise = new Promise<void>((resolve) => {
      writer.on('closed', (writer: MCMediaContentWriter) => {
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Writer closed for content.`);

        this.mWriter = undefined;
        this.mWritePromise = undefined;
        writer.off('closed');
        resolve();
      });
    });
    return this.mWriter;
  }

  destroy(): Promise<void> {
    const waits = new Array<Promise<void>>();
    if ( this.mReadPromiseLink ) {
      waits.push(this.mReadPromiseLink);
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Waiting for read operations to finish before destroying content.`);
    }
    if ( this.mWritePromise ) {
      waits.push(this.mWritePromise);
      MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Waiting for write operations to finish before destroying content.`);
    }
    return waits.length > 0 ? Promise.all(waits).then(() => this.deleteFile()) : this.deleteFile();
  }

  on(_: "dataWritten", callback: (content: IMCMediaContent) => void): void {
    this.mDataWrittenCallback = callback;
  }

  off(_: "dataWritten"): void {
    this.mDataWrittenCallback = undefined;
  }

  private onDataWritten(): void {
    setTimeout(() => {
      if (this.mDataWrittenCallback) {
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Executing dataWritten callback.`);
        this.mDataWrittenCallback(this);
      }
      else {
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] No dataWritten callback to execute.`);
      }
    });
  }

  private async deleteFile(): Promise<void> {
    this.mDestroyed = true;

    try {
      await fileIo.unlink(this.filePath);
      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] File deleted successfully: ${this.filePath}.`);
    }
    catch (e) {
      MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Failed to delete file: ${this.filePath}. Error: ${e.message}.`);
    }

    MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Content destroyed successfully.`);
  }
}