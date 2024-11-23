import { IMCMedia } from "../common/IMCMedia";
import { IMCMediaDataReadRequest } from "../common/IMCMediaDataReadRequest";
import { http } from "@kit.NetworkKit";
import { IMCMediaContentLoader } from "../common/IMCMediaContentLoader";
import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCReadwriteReference } from "../common/MCReadwriteReference";
import { MCMediaContentProvider } from "./MCMediaContentProvider";

export class MCMedia extends MCReadwriteReference<MCMedia> implements IMCMedia {
  readonly id: string;
  private mContentType?: string = undefined;
  private mTotalLength = 0;
  private mByteRangeAccessSupported = false;
  private mStored = false;
  private mContentProvider?: MCMediaContentProvider = undefined;

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

  prepare(rootDir: string): Promise<void> {
    return this.mLock.lockAsync(async () => {
      this.mContentProvider = new MCMediaContentProvider(rootDir, this.id);
      const contents = await this.mContentProvider.prepare();

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