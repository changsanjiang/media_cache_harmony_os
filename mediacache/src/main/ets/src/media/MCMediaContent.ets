import { IMCMediaContent, IMCMediaContentReader, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCMediaContentReader } from "./MCMediaContentReader";
import { MCMediaContentWriter } from "./MCMediaContentWriter";
import { fileIo } from "@kit.CoreFileKit";
import { MCAbortController } from "../utils/MCAbortController";

export class MCMediaContent implements IMCMediaContent {
  private mLength = 0;
  private mDestroyed = false;
  private mWriter?: MCMediaContentWriter = undefined;
  private mDataWrittenCallback?: (content: IMCMediaContent) => void = undefined;
  private mTemp = false; // 是否是临时内容
  private mAbortController = new MCAbortController();

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

    const reader = new MCMediaContentReader(this, this.mAbortController.signal);
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

    const writer = new MCMediaContentWriter(this, this.mAbortController.signal);
    this.mWriter = writer;
    writer.on('dataWritten', (_: MCMediaContentWriter, length: number) => {
      this.mLength += length;
      this.onDataWritten();
    });

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

      try {
        await this.mAbortController.abort(new Error('Operation aborted.'));
        MCLogger.debug(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Abort signal sent.`);
      }
      catch (error) {
        MCLogger.warn(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Failed to send abort signal. Error: ${error.message}.`);
      }

      try {
        await fileIo.unlink(this.filePath);
        MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] File deleted successfully: ${this.filePath}.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Failed to delete file: ${this.filePath}. Error: ${error.message}.`);
      }

      MCLogger.info(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Media content destroyed successfully.`);
    }
    else {
      MCLogger.warn(MCLogModule.MCMediaContent, () => `[media: ${this.mediaId}, offset: ${this.contentOffset}] Destroy called on already destroyed media content.`);
    }
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
}