import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";
import { MCMediaContentProvider } from "./MCMediaContentProvider";
import { MCMediaContentNodeList } from "./MCMediaContentNodeList";
import { IMCMediaContentNode } from "../defines/IMCMediaContentNode";
import { MCRange } from "../utils/MCRange";
import MCDatabase from "../utils/MCDatabase";
import { IMCMediaMetadata } from "../defines/IMCMediaMetadata";
import { parseResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCProxyURL from "../utils/MCProxyURL";
import { MCMediaHttpContentLoader } from "./MCMediaHttpContentLoader";
import { parseRequestRange, toRequestRange } from "../defines/IMCHttpRequestRange";
import { MCMediaFileContentLoader } from "./MCMediaFileContentLoader";
import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { MCLogModule } from "../defines/MCLogModule";
import { MCMediaContent } from "./MCMediaContent";

export class MCMedia extends MCReadwriteReference<MCMedia> implements IMCMedia {
  readonly id: string;
  private mDir: string;
  private mMetadata?: IMCMediaMetadata = undefined;
  private mContentProvider?: MCMediaContentProvider = undefined;
  private mNodeList = new MCMediaContentNodeList();
  private mAssembled = false; // 是否已组合完成, 是否已得到完整内容; 虽然得到了完整内容, 但是文件夹下可能还存在正在读取的冗余数据;
  private mFullyTrimmed = false; // 所有冗余数据都已删除;

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${id}]: MCMedia instance created with dir ${dir}.`);
  }

  get metadataReady(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mMetadata !== undefined);
  }
  get contentType(): Promise<string | undefined> {
    return this.mLock.lockAsync(() => this.mMetadata?.contentType);
  }
  get totalLength(): Promise<number> {
    return this.mLock.lockAsync(() => this.mMetadata ? this.mMetadata.totalLength : 0);
  }
  get isStored(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAssembled);
  }
  // 完成度: [0, 1];
  get completeness(): Promise<number> {
    return this.mLock.lockAsync(async () => {
      if (this.mAssembled) {
        return 1;
      }

      if (!this.mMetadata || !this.mNodeList.head) {
        return 0;
      }

      let lengthCached = 0;
      let prevMax = 0;
      let node: IMCMediaContentNode | undefined = this.mNodeList.head;
      while (node) {
        const content = node.longestContent;
        if ( content ) {
          const offset = content.contentOffset;
          const length = await content.length;
          lengthCached += length;
          if ( prevMax > offset ) lengthCached -= (prevMax - offset);
          prevMax = offset + length;
        }
        node = node.next;
      }
      return lengthCached * 1.0 / this.mMetadata.totalLength;
    });
  }

  async prepare(): Promise<void> {
    return this.mLock.lockAsync(async () => {
      MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Preparing media`);
      try {
        this.mContentProvider = new MCMediaContentProvider(this.id, this.mDir, this.id);
        const contents = await this.mContentProvider.prepare();
        contents?.forEach((content) => this.mNodeList.upsertNode(content.contentOffset, content));
        this.mMetadata = await MCDatabase.queryMediaMetadata(this.id);
        if (this.mMetadata) {
          MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Metadata loaded. ContentType: ${this.mMetadata?.contentType}, TotalLength: ${this.mMetadata?.totalLength}.`);
          if (this.mMetadata.totalLength !== 0) {
            this.restructureContents();
          }
          else {
            this.mAssembled = true;
            this.mFullyTrimmed = true;
          }
        }
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during preparation: ${error.message}\nStack: ${error.stack}`);
        throw error as Error;
      }
    });
  }

  getContentLoadersBy(proxyRequest: IMCHttpRequest): Promise<IMCMediaContentLoader[]> {
    return this.mLock.lockAsync(async () => {
      MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Resolving content loaders for request: ${JSON.stringify(proxyRequest)}.`);
      try {
        const url = MCProxyURL.restoreURLFromProxyTarget(proxyRequest.requestTarget);
        if (!url) {
          throw new Error("Failed to restore URL from the provided proxy target.");
        }

        const loaders: IMCMediaContentLoader[] = [];
        if (this.mMetadata && this.mMetadata.totalLength !== 0 && this.mNodeList.head) {
          const requestRangeHeader = proxyRequest.headers['range'];
          const totalLength = this.mMetadata.totalLength;
          let loadRange = requestRangeHeader ? this.parseLoadRange(requestRangeHeader, totalLength) : new MCRange(0, totalLength);
          let curNode: IMCMediaContentNode | undefined = this.mNodeList.findClosestLeftNode(loadRange.location) ?? this.mNodeList.head;

          MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Load range parsed as: ${JSON.stringify(loadRange)}`);

          while (curNode) {
            // 获取当前长度最长的内容
            const content = curNode.longestContent!; // 每个节点中都包含至少一个内容;
            // 可读取的范围
            const readableRange = new MCRange(content.contentOffset, await content.length);
            const intersection = loadRange.intersection(readableRange);
            // 如果存在交集
            if ( intersection ) {
              // 获取左侧未下载的部分
              if ( intersection.location > loadRange.location ) {
                const leftRange = new MCRange(loadRange.location, intersection.location - loadRange.location);
                loaders.push(new MCMediaHttpContentLoader(this, {
                  url: url,
                  range: toRequestRange(leftRange),
                  headers: proxyRequest.headers,
                }));
              }
              loaders.push(new MCMediaFileContentLoader(await content.readwriteRetain(), intersection));
              loadRange = new MCRange(intersection.max, loadRange.max - intersection.max);
            }
            if ( loadRange.length === 0 || readableRange.location > loadRange.max ) {
              break;
            }
            curNode = curNode.next;
          }
          // 剩余未下载的部分;
          if (loadRange.length !== 0) {
            loaders.push(new MCMediaHttpContentLoader(this, {
              url: url,
              range: toRequestRange(loadRange),
              headers: proxyRequest.headers,
            }));
          }
        }
        else if (this.mMetadata && this.mMetadata.totalLength !== 0) { // empty content;
          const emptyContent = new MCMediaContent(this.id, 0, '');
          loaders.push(new MCMediaFileContentLoader(await emptyContent.readwriteRetain(), new MCRange(0, 0)));
        }
        else {
          loaders.push(new MCMediaHttpContentLoader(this, {
            url: url,
            headers: proxyRequest.headers
          }));
        }

        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Resolved ${loaders.length} loaders.`);
        return loaders;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error while resolving content loaders: ${error.message}\nStack: ${error.stack}`);
        throw error as Error;
      }
    });
  }

  createContentBy(headers: MCDownloadResponseHeaders): Promise<IMCMediaContent> {
    /** response headers
     - 206
     {
       "accept-ranges": "bytes",
       "content-length": "3",
       "content-range": "bytes 0-2/59471774",
       "content-type": "video/mp4"
     }

     - 200
     {
       "accept-ranges": "bytes",
       "content-length": "60277",
       "content-type": "image/jpeg"
     }
     */
    return this.mLock.lockAsync(async () => {
      MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Creating content by headers: ${JSON.stringify(headers)}.`);

      try {
        const acceptRangesHeader: string | undefined = headers['accept-ranges'];
        const contentRangeHeader: string | undefined = headers['content-range'];
        const contentTypeHeader: string | undefined = headers['content-type'];
        const contentLengthHeader: string | undefined = headers['content-length'];

        if (!contentLengthHeader) {
          const errorMsg = "Missing 'content-length' in response headers.";
          MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: ${errorMsg}`);
          throw new Error(errorMsg);
        }

        const contentRange = contentRangeHeader ? parseResponseContentRange(contentRangeHeader) : undefined;
        const contentType = contentTypeHeader || 'application/octet-stream';
        const contentLength = parseInt(contentLengthHeader, 10);
        const totalLength = contentRange ? contentRange.size : contentLength;

        const byteRangeAccessSupported = acceptRangesHeader === 'bytes' || contentRange !== undefined;
        if (totalLength !== 0 && !byteRangeAccessSupported) {
          const errorMsg = "Byte range access not supported by server. Missing 'accept-ranges' or 'content-range'.";
          MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: ${errorMsg}`);
          throw new Error(errorMsg);
        }

        if ( !this.mMetadata ) {
          const metadata: IMCMediaMetadata = {
            contentType: contentType,
            totalLength: totalLength,
          };
          this.mMetadata = metadata;
          await MCDatabase.saveMediaMetadata(this.id, metadata);
          MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Metadata saved. ContentType: ${contentType}, TotalLength: ${totalLength}.`);
        }

        const contentOffset = contentRange ? contentRange.rangeStart : 0;
        const content = this.mContentProvider!.createContent(contentOffset);
        this.mNodeList.upsertNode(contentOffset, content);
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Content created at offset: ${contentOffset}.`);
        return content.readwriteRetainUnsafe();
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error in createContentBy: ${error.message}\nStack: ${error.stack}`);
        throw error as Error;
      }
    });
  }

  protected getInstance(): MCMedia {
    return this;
  }

  // 该方法被回调时, 不仅仅当前 media 的读写计数为 0, 所有的 content 的读写计数也都为 0;
  protected onReadwriteZeroReferences(): void {
    if ( !this.mFullyTrimmed && this.mMetadata ) {
      this.restructureContents();
    }
  }

  // 重组内容. 合并数据并移除多余内容;
  private async restructureContents(): Promise<void> {
    if ( !this.mFullyTrimmed && this.mMetadata ) {
      try {
        const head = this.mNodeList.head;
        let curNode = head;

        while (curNode) {
          if ( curNode.numberOfContents > 1 ) {
            await this.trimRedundantContents(curNode);
          }
          const nextNode = curNode.next;
          if ( !nextNode ) break;  // break;

          if ( nextNode.numberOfContents > 1 ) {
            await this.trimRedundantContents(curNode);
          }

          const writer = curNode.longestContent;
          const reader = nextNode.longestContent;
          let isNextNodeRemoved = false;

          if ( writer && reader ) {
            const isMerged = await this.mergeData(writer, reader);
            if ( isMerged ) {
              await reader.destroyUnsafe();
              nextNode.removeContent(reader);
              MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Merged content from nextNode into currentNode.`);
              if ( nextNode.numberOfContents == 0 ) {
                this.mNodeList.removeNode(nextNode);
                isNextNodeRemoved = true;
                MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Removed empty nextNode.`);
              }
            }
            if ( !isNextNodeRemoved ) {
              curNode = nextNode;
            }
          }

          // 执行 restructureContents 时, 当前 media 的读写计数为 0, 所以访问 content 的 length 直接通过 unsafeLength 获取即可, 无需加锁;
          if (head && head.longestContent?.lengthUnsafe === this.mMetadata.totalLength) {
            this.mAssembled = true;
            this.mFullyTrimmed = this.mNodeList.count === 1 && head.numberOfContents === 1;
            MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Content restructuring completed. Assembled: ${this.mAssembled}, FullyTrimmed: ${this.mFullyTrimmed}.`);
            break;
          }
        }
      } catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during content restructuring: ${error.message}\nStack: ${error.stack}`);
        throw error as Error;
      }
    }
  }

  private async trimRedundantContents(node: IMCMediaContentNode): Promise<void> {
    if ( node.numberOfContents > 1 ) {
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Trimming redundant contents for node at offset: ${node.placement}.`);

      // 同一段位置可能存在多个文件
      // 删除多余的无用的content
      const longestContent = node.longestContent!;
      const redundantContents = node.filterContents((content) => content !== longestContent);
      for (let content of redundantContents) {
        await content.destroyUnsafe();
        node.removeContent(content);
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Destroyed redundant content at offset: ${content.contentOffset}.`);
      }
    }
  }

  // 合并数据; 被合并后返回 true;
  // writer.contentOffset <= reader.contentOffset;
  private async mergeData(writer: IMCMediaContent, reader: IMCMediaContent): Promise<boolean> {
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Attempting to merge data between writer at offset ${writer.contentOffset} and reader at offset ${reader.contentOffset}.`);
    if ( writer.contentOffset > reader.contentOffset ) {
      // writer的内容偏移量 必须在 reader 的前面, 这样才能在存在交集时合并数据;
      const errorMsg = `Invalid offsets: writer offset (${writer.contentOffset}) must be less than or equal to reader offset (${reader.contentOffset}).`;
      MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: ${errorMsg}`);
      throw new Error(errorMsg);
    }

    const curRange = new MCRange(writer.contentOffset, writer.lengthUnsafe);
    const nextRange = new MCRange(reader.contentOffset, reader.lengthUnsafe);
    // 如果 writer 中包含 reader 的所有数据, return YES;
    if (curRange.contains(nextRange)) {
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Writer range fully contains reader range. Skipping merge.`);
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
        writer.readwriteRetainUnsafe();
        reader.readwriteReleaseUnsafe();
        while (position < readRange.max) {
          const len = await reader.readDataUnsafe(position, buffer, buffer.byteLength);
          if (len === 0) break;
          position += await writer.writeDataUnsafe(buffer, len);
        }
        writer.readwriteReleaseUnsafe();
        reader.readwriteReleaseUnsafe();
        await reader.closeReadUnsafe();
        await writer.closeWriteUnsafe();

        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Merge completed. Data from reader successfully written to writer.`);
        return true;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during merge: ${error.message}\nStack: ${error.stack}`);
        await writer.readwriteRelease();
        await reader.readwriteRelease();
        throw error as Error;
      }
    }
    MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Ranges are not intersecting or contiguous. No merge performed.`);
    return false;
  }

  private parseLoadRange(requestRangeHeader: string, totalLength: number): MCRange {
    if (!requestRangeHeader) {
      throw new Error("Missing range header in the request.");
    }

    const requestRange = parseRequestRange(requestRangeHeader);
    const requestRangeStart = requestRange.rangeStart;
    const requestRangeEnd = requestRange.rangeEnd;
    const requestSuffixLength = requestRange.suffixLength;

    // 检查范围合法性;
    if ( requestRangeStart && requestRangeStart >= totalLength ) {
      throw new Error('Invalid range: requestRangeStart exceeds total media length.');
    }
    if ( requestRangeEnd && requestRangeEnd >= totalLength ) {
      throw new Error('Invalid range: requestRangeEnd exceeds total media length.');
    }
    if ( requestSuffixLength && requestSuffixLength >= totalLength ) {
      throw new Error('Invalid range: requestSuffixLength exceeds total media length.');
    }

    // 转为 range;
    let rangeStart: number | undefined;
    let rangeEnd: number | undefined;

    if ( requestSuffixLength ) {
      rangeStart = totalLength - requestSuffixLength;
      rangeEnd = totalLength - 1;
    }
    else if ( requestRangeEnd ) {
      rangeStart = requestRangeStart!;
      rangeEnd = requestRangeEnd;
    }
    else {
      rangeStart = requestRangeStart!;
      rangeEnd = totalLength - 1;
    }
    return new MCRange(rangeStart, rangeEnd + 1 - rangeStart);
  }
}