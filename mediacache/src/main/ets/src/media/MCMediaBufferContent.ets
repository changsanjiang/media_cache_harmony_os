import { IMCMediaContent, IMCMediaContentReader, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCCopyFileConflictStrategy } from "../defines/MCCopyFileConflictStrategy";
import { MCLogModule } from "../defines/MCLogModule";
import MCFileIOUtils from "../utils/MCFileIOUtils";
import MCLogger from "../utils/MCLogger";

export class MCMediaBufferContent implements IMCMediaContent {
  private mMediaId: string;
  private mContentOffset: number;
  private mBufferHolder: Holder;
  private mTemp: boolean;
  private mDataWrittenCallback?: (content: IMCMediaContent) => void = undefined;
  private mLength: number;
  private mDestroyed = false;
  private mWriter?: IMCMediaContentWriter = undefined;

  constructor(mediaId: string, contentOffset: number, buffer?: ArrayBuffer, isTemp?: boolean) {
    this.mMediaId = mediaId;
    this.mContentOffset = contentOffset;
    this.mBufferHolder = { buffer: buffer };
    this.mLength = buffer?.byteLength ?? 0;
    this.mTemp = isTemp ?? false;
  }

  get mediaId(): string {
    return this.mMediaId;
  }

  get contentOffset(): number {
    return this.mContentOffset;
  }

  get length(): number {
    return this.mLength;
  }

  get isTemp(): Boolean {
    return this.mTemp;
  }

  get isDestroyed(): boolean {
    return this.mDestroyed;
  }

  get holder(): Holder {
    return this.mBufferHolder;
  }

  createReader(): IMCMediaContentReader {
    if ( this.mDestroyed ) {
      throw new Error("Content has been destroyed, cannot create reader.");
    }

    const reader = new MCMediaBufferContentReader(this);
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Reader created for content.`);
    return reader;
  }

  createWriter(): IMCMediaContentWriter {
    if ( this.mDestroyed ) {
      throw new Error("Content has been destroyed, cannot create writer.");
    }

    if ( this.mWriter && !this.mWriter.isClosed ) {
      throw new Error("Only one writer can be created."); // 只允许创建一个writer写入数据, 不能创建多个writer写入数据;
    }

    this.mWriter = new MCMediaBufferContentWriter(this);
    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Writer created for content.`);
    return this.mWriter;
  }

  get hasWriter(): boolean {
    return this.mWriter == undefined || this.mWriter.isClosed;
  }

  finalize(): void {
    this.mTemp = false;
  }

  async destroy(): Promise<void> {
    if (!this.mDestroyed) {
      this.mDestroyed = true;
      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Destroying media content.`);
    }
  }

  async copyFile(destPath: string, conflictStrategy?: MCCopyFileConflictStrategy | undefined): Promise<void> {
    const buffer = this.mBufferHolder.buffer;
    if ( buffer ) {
      return MCFileIOUtils.writeFile(buffer, destPath, conflictStrategy);
    }
  }

  on(event: "dataWritten", callback: (content: IMCMediaContent) => void): void {
    this.mDataWrittenCallback = callback;
  }

  off(event: "dataWritten"): void {
    this.mDataWrittenCallback = undefined;
  }

  onDataWritten(length: number): void {
    this.mLength += length;
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
}

interface Holder {
  buffer: ArrayBuffer | undefined;
}

class MCMediaBufferContentReader implements IMCMediaContentReader {
  private mContent: MCMediaBufferContent;
  private mClosed = false;

  constructor(content: MCMediaBufferContent) {
    this.mContent = content;
  }

  get isClosed(): boolean {
    return this.mClosed;
  }

  async readData(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    const mediaId = this.mContent.mediaId;
    const contentOffset = this.mContent.contentOffset;
    const contentLength = this.mContent.length;
    const contentBuffer = this.mContent.holder.buffer;

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}, offset: ${contentOffset}] Attempting to read data at position ${position} with length ${length}.`);

    if ( buffer.byteLength === 0 ) {
      throw new Error("Buffer cannot be empty.");
    }

    if ( this.mClosed ) {
      throw new Error("Reader has been closed, cannot proceed with reading.");
    }

    if ( this.mContent.isDestroyed ) {
      throw new Error("Content has been destroyed, cannot proceed with reading.");
    }

    if ( position < contentOffset || position >= contentOffset + contentLength ) {
      throw new Error(`Position ${position} is out of valid range [${contentOffset}, ${contentOffset + contentLength}).`);
    }

    if ( !contentBuffer ) {
      throw new Error("No content buffer for reading.");
    }

    const readOffset = position - contentOffset;
    const available = contentLength - readOffset;
    const readLength = Math.min(buffer.byteLength, length);

    if (readLength <= 0) {
      MCLogger.warn(MCLogModule.MCMediaContent, () => `[media: ${mediaId}] Nothing to read at position=${position} (available=${available}).`);
      return 0;
    }

    MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${mediaId}] Reading from offset=${readOffset}, readLength=${readLength}.`);

    const src = new Uint8Array(contentBuffer, readOffset, readLength);
    const dst = new Uint8Array(buffer, 0, readLength);
    dst.set(src);

    MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${mediaId}] Successfully read ${readLength} bytes from position=${position}.`);
    return readLength;
  }

  async close(error?: Error | undefined): Promise<void> {
    this.mClosed = true;
  }
}

class MCMediaBufferContentWriter implements IMCMediaContentWriter {
  private mContent: MCMediaBufferContent;
  private mClosed = false;

  constructor(content: MCMediaBufferContent) {
    this.mContent = content;
  }

  get isClosed(): boolean {
    return this.mClosed;
  }

  async writeData(data: ArrayBuffer, length: number): Promise<number> {
    if (data.byteLength < length) {
      throw new Error(`Data length mismatch: provided data is smaller than expected length. provided=${data.byteLength}, expected=${length}`);
    }

    if ( this.mClosed ) {
      throw new Error("Writer has been closed, cannot proceed with writing.");
    }

    if ( this.mContent.isDestroyed ) {
      throw new Error("Content has been destroyed, cannot proceed with writing.");
    }

    const mediaId = this.mContent.mediaId;
    const oldBuffer = this.mContent.holder.buffer || new ArrayBuffer(0);
    const oldLength = oldBuffer.byteLength;

    const writeLength = Math.min(length, data.byteLength);
    const newBuffer = new ArrayBuffer(oldLength + writeLength);

    new Uint8Array(newBuffer, 0, oldLength).set(new Uint8Array(oldBuffer));
    new Uint8Array(newBuffer, oldLength, writeLength).set(new Uint8Array(data, 0, writeLength));

    this.mContent.holder.buffer = newBuffer;
    this.mContent.onDataWritten(writeLength);

    MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${mediaId}] Successfully wrote ${writeLength} bytes, new total size=${newBuffer.byteLength}.`);
    return writeLength;
  }

  async close(error?: Error | undefined): Promise<void> {
    this.mClosed = true;
  }
}