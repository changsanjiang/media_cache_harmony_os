import { IMCMedia } from "../common/IMCMedia";
import { IMCMediaDataReadRequest } from "../common/IMCMediaDataReadRequest";
import { http } from "@kit.NetworkKit";
import { IMCMediaContentLoader } from "../common/IMCMediaContentLoader";
import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCReadwriteReference } from "../common/MCReadwriteReference";
import { MCMediaContentProvider } from "./MCMediaContentProvider";
import { MCMediaContentNodeList } from "./MCMediaContentNodeList";
import { IMCMediaContentNode } from "../common/IMCMediaContentNode";
import { MCRange } from "../utils/MCRange";
import MCDatabase from "../common/MCDatabase";

export class MCMedia extends MCReadwriteReference<MCMedia> implements IMCMedia {
  readonly id: string;
  private mMetadata?: MCDatabase.IMCMediaMetadata = undefined;
  private mContentProvider?: MCMediaContentProvider = undefined;
  private mNodeList = new MCMediaContentNodeList();
  private mAssembled = false; // 是否已组合完成, 是否已得到完整内容; 虽然得到了完整内容, 但是文件夹下可能还存在正在读取的冗余数据;
  private mFullyTrimmed = false; // 所有冗余数据都已删除;

  constructor(id: string) {
    super();
    this.id = id;
  }

  get contentType(): Promise<string | undefined> {
    return this.mLock.lockAsync(() => this.mMetadata?.contentType);
  }
  get totalLength(): Promise<number> {
    return this.mLock.lockAsync(() => this.mMetadata ? this.mMetadata.totalLength : 0);
  }
  get byteRangeAccessSupported(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mMetadata ? this.mMetadata.byteRangeAccessSupported : false);
  }
  get isStored(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAssembled);
  }
  get completeness(): Promise<number> {
    throw new Error("Method not implemented.");
  }

  async prepare(rootDir: string): Promise<void> {
    return this.mLock.lockAsync(async () => {
      this.mContentProvider = new MCMediaContentProvider(rootDir, this.id);
      const contents = await this.mContentProvider.prepare();
      contents?.forEach((content) => this.mNodeList.upsertNode(content.contentOffset, content));
      this.mMetadata = await MCDatabase.queryMediaMetadata(this.id);
      if ( this.mMetadata ) {
        this.restructureContents();
      }
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

  // 重组内容. 合并数据并移除多余内容;
  private async restructureContents(): Promise<void> {
    if ( !this.mFullyTrimmed && this.mMetadata ) {
      const head = this.mNodeList.head;
      let curNode = head;
      while (curNode) {
        if ( curNode.numberOfContents > 1 ) {
          this.trimRedundantContents(curNode);
        }
        const nextNode = curNode.next;
        if ( !nextNode ) break;  // break;
        if ( nextNode.numberOfContents > 1 ) {
          this.trimRedundantContents(curNode);
        }
        const writer = curNode.longestContent;
        const reader = nextNode.longestContent;
        let isNextNodeRemoved = false;
        if ( writer != null && reader != null ) {
          const isMerged = await this.mergeData(writer, reader);
          if ( isMerged ) {
            await reader.destroy();
            nextNode.removeContent(reader);
            if ( nextNode.numberOfContents == 0 ) {
              this.mNodeList.removeNode(nextNode);
              isNextNodeRemoved = true;
            }
          }
          if ( !isNextNodeRemoved ) {
            curNode = nextNode;
          }
        }
        if ( head && head.longestContent?.unsafeLength === this.mMetadata.totalLength ) {
          if ( !this.mAssembled ) {
            this.mAssembled = true;
            //     for ( id<MCSAssetObserver> observer in MCSAllHashTableObjects(mObservers) ) {
            //       if ( [observer respondsToSelector:@selector(assetDidStore:)] ) {
            //         [observer assetDidStore:self];
            //       }
            //     }
          }

          if ( !this.mFullyTrimmed ) {
            this.mFullyTrimmed = this.mNodeList.count === 1 && head.numberOfContents === 1;
          }
        }
      }
    }
  }

  private trimRedundantContents(node: IMCMediaContentNode): void {
    if ( node.numberOfContents > 1 ) {
      // 同一段位置可能存在多个文件
      // 删除多余的无用的content
      const longestContent = node.longestContent!;
      node.trimExcessContentsWithTest((content) => {
        if ( content !== longestContent ) {
          content.destroy();
          return true;
        }
        return false;
      });
    }
  }

  // 合并数据; 被合并后返回 true;
  private async mergeData(writer: IMCMediaContent, reader: IMCMediaContent): Promise<boolean> {
    const curRange = new MCRange(writer.contentOffset, writer.unsafeLength);
    const nextRange = new MCRange(reader.contentOffset, reader.unsafeLength);
    // 如果 writer 中包含 reader 的所有数据, return YES;
    if (curRange.contains(nextRange)) {
      return true;
    }

    // 判断是否连续的 或 存在交集;
    // 合并未相交部分的数据;
    if ( curRange.max === nextRange.location || curRange.isIntersecting(nextRange) ) {
      const capacity = 4 * 1024 * 1024;
      const buffer = new ArrayBuffer(capacity);
      // 读取 read 中未相交的部分;
      const readRange = new MCRange(curRange.max, nextRange.max - curRange.max);
      let position = readRange.location;
      try {
        await writer.readwriteRetain();
        await reader.readwriteRelease();
        while (true) {
          const len = await reader.readData(position, buffer);
          if (len == 0) {
            break;
          }
          position += await writer.writeData(buffer, len);
          if (position == readRange.max) {
            break;
          }
        }
      }
      catch (e) {
        writer.readwriteRelease();
        reader.readwriteRelease();
        return Promise.reject(e);
      }
      await writer.readwriteRelease();
      await reader.readwriteRelease();
      await reader.closeRead();
      await writer.closeWrite();
      return true;
    }
    return false;
  }
}