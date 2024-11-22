import { IMCMedia } from "../common/IMCMedia";
import { IMCMediaDataReadRequest } from "../common/IMCMediaDataReadRequest";
import { http } from "@kit.NetworkKit";
import { IMCMediaContentLoader } from "../common/IMCMediaContentLoader";
import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCReadwriteReference } from "../common/MCReadwriteReference";

export class MCMedia extends MCReadwriteReference<MCMedia> implements IMCMedia {
  readonly id: string;
  private mContentType?: string = undefined;
  private mTotalLength = 0;
  private mByteRangeAccessSupported = false;
  private mStored = false;

  constructor(id: string) {
    super();
    this.id = id;
  }

  get contentType(): Promise<string | undefined> {
    return this.mLock.lockAsync(() => this.mContentType);
  }
  get totalLength(): Promise<number> {
    return this.mLock.lockAsync(() => this.mTotalLength);
  }
  get byteRangeAccessSupported(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mByteRangeAccessSupported);
  }
  get isStored(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mStored);
  }
  get completeness(): Promise<number> {
    throw new Error("Method not implemented.");
  }

  prepare(): Promise<void> {
    return this.mLock.lockAsync(() => {
      // TODO: 从磁盘加载已缓存的内容

    })
  }

  getContentLoadersBy(request: IMCMediaDataReadRequest): Promise<IMCMediaContentLoader[]> {
    throw new Error("Method not implemented.");
  }

  createContentBy(response: http.HttpResponse): Promise<IMCMediaContent> {
    throw new Error("Method not implemented.");
  }

  protected getInstance(): MCMedia {
    return this;
  }

  protected onReadwriteZeroReferences(): void {

  }
}