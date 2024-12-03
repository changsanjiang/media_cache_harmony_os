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
import { generateResponseContentRange, parseResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCURL from "../utils/MCURL";
import { MCMediaHttpContentLoader } from "./MCMediaHttpContentLoader";
import { parseRequestRange, toRequestRange, toRequestRangeHeader } from "../defines/IMCHttpRequestRange";
import { MCMediaFileContentLoader } from "./MCMediaFileContentLoader";
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";
import { MCMediaContent } from "./MCMediaContent";
import MCDownload from "../utils/MCDownload";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import { IMCDataOkResponse, IMCDataPartialContentResponse, IMCDataResponse } from "../defines/IMCDataResponse";
import { MCDataResponseError } from "../defines/MCDataResponseError";

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

  get metadataReady(): boolean {
    return this.mMetadata !== undefined;
  }
  get contentType(): string | undefined {
    return this.mMetadata?.contentType;
  }
  get totalLength(): number {
    return this.mMetadata?.totalLength ?? 0;
  }
  get isStored(): Promise<boolean> {
    return Promise.resolve(this.mAssembled);
  }
  // 完成度: [0, 1];
  get completeness(): Promise<number> {
    return this.calculateCompleteness();
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Preparing media`);
    try {
      this.mContentProvider = new MCMediaContentProvider(this.id, this.mDir, this.id);
      const contents: IMCMediaContent[] | undefined = [];// await this.mContentProvider.prepare();
      contents?.forEach((content) => this.mNodeList.upsertNode(content.contentOffset, content));
      this.mMetadata = await MCDatabase.queryMediaMetadata(this.id);
      if (this.mMetadata) {
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Metadata loaded. ContentType: ${this.mMetadata?.contentType}, TotalLength: ${this.mMetadata?.totalLength}, ByteRangeAccessSupported: ${this.mMetadata?.byteRangeAccessSupported}.`);
        if      (this.mMetadata.totalLength === Number.MAX_SAFE_INTEGER) {
          await this.mContentProvider.removeAllTempContentFiles();
        }
        else if (this.mMetadata.totalLength !== 0) {
          await this.restructureContents();
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
  }

  fetch(request: IMCDataRequest): Promise<IMCDataResponse> {
    return this.probe(request).then(() => this.resolve(request)).catch((error: Error) => {
      let statusCode = 500;
      if ( error instanceof MCDataResponseError ) {
        statusCode = error.statusCode;
      }
      const response: IMCDataResponse = {
        statusCode: statusCode
      };
      return response;
    });
  }

  // 探测元数据
  private async probe(proxyRequest: IMCDataRequest): Promise<void> {
    if ( this.mMetadata ) {
      return;
    }

    const requestTarget = proxyRequest.requestTarget;
    const headers = proxyRequest.headers;
    const mediaUrl = MCURL.parseUrl(requestTarget);
    const request = new MCDownload.Request(mediaUrl, headers);

    return MCDownload.probe(request).then(async (response) => {
      if ( this.mMetadata ) {
        return;
      }

      const statusCode = response.statusCode;
      if ( statusCode != 200 && statusCode != 206 ) {
        throw new MCDataResponseError(statusCode, 'xxx');
      }

      // 探测服务器支持的情况
      // 如果不支持206请求，在未完全下载之前就只创建一个 200 loader

      const headers = response.headers;
      const acceptRangesHeader: string | undefined = headers['accept-ranges'];
      const contentRangeHeader: string | undefined = headers['content-range'];
      const contentTypeHeader: string | undefined = headers['content-type'];
      const contentLengthHeader: string | undefined = headers['content-length'];

      const contentType = contentTypeHeader || 'application/octet-stream';
      const byteRangeAccessSupported = statusCode === 206 || acceptRangesHeader === 'bytes';

      const contentLength = contentLengthHeader ? parseInt(contentLengthHeader, 10) : Number.MAX_SAFE_INTEGER;
      const contentRange = contentRangeHeader ? parseResponseContentRange(contentRangeHeader) : undefined;
      const totalLength = contentRange ? contentRange.size : contentLength;

      const metadata: IMCMediaMetadata = {
        contentType: contentType,
        totalLength: totalLength,
        byteRangeAccessSupported: byteRangeAccessSupported
      };
      await MCDatabase.saveMediaMetadata(this.id, metadata);
      this.mMetadata = metadata;
    });
  }

  private async resolve(proxyRequest: IMCDataRequest): Promise<IMCDataResponse> {
    const url = MCURL.parseUrl(proxyRequest.requestTarget);
    if (!url) {
      throw new MCDataResponseError(400, "Failed to restore URL from the provided request.");
    }
    const metadata = this.mMetadata!;
    const contentType = metadata.contentType;
    const totalLength = metadata.totalLength;
    const contentLoaders: IMCMediaContentLoader[] = [];
    if (metadata.byteRangeAccessSupported && metadata.totalLength > 0 && this.mNodeList.head) {
      const requestRangeHeader = proxyRequest.headers['range'];
      const contentRange = requestRangeHeader ? this.parseLoadRange(requestRangeHeader, totalLength) : new MCRange(0, totalLength);

      let loadRange = new MCRange(contentRange.location, contentRange.length);
      let curNode: IMCMediaContentNode | undefined = this.mNodeList.findClosestLeftNode(loadRange.location) ?? this.mNodeList.head;

      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Load range parsed as: ${JSON.stringify(loadRange)}`);

      while (curNode) {
        // 获取当前长度最长的内容
        const content = curNode.longestContent!; // 每个节点中都包含至少一个内容;
        // 可读取的范围
        const readableRange = new MCRange(content.contentOffset, content.length);
        const intersection = loadRange.intersection(readableRange);
        // 如果存在交集
        if ( intersection ) {
          // 获取左侧未下载的部分
          if ( intersection.location > loadRange.location ) {
            const leftRange = new MCRange(loadRange.location, intersection.location - loadRange.location);
            const leftRequest = new MCDownloadRequest(url, proxyRequest.headers);
            leftRequest.setHeader('range', toRequestRangeHeader(toRequestRange(leftRange)));
            contentLoaders.push(new MCMediaHttpContentLoader(this, leftRequest));
          }
          contentLoaders.push(new MCMediaFileContentLoader(content.readwriteRetain(), intersection));
          loadRange = new MCRange(intersection.max, loadRange.max - intersection.max);
        }
        if ( loadRange.length === 0 || readableRange.location > loadRange.max ) {
          break;
        }
        curNode = curNode.next;
      }

      // 剩余未下载的部分;
      if (loadRange.length !== 0) {
        const request = new MCDownloadRequest(url, proxyRequest.headers);
        request.setHeader('range', toRequestRangeHeader(toRequestRange(loadRange)));
        contentLoaders.push(new MCMediaHttpContentLoader(this,request));
      }

      const response: IMCDataPartialContentResponse = {
        statusCode: 206,
        contentType: contentType,
        contentRange: contentRange,
        totalLength: totalLength,
        contentLoaders: contentLoaders
      };
      return response;
    }
    else if (metadata.totalLength === 0) { // empty content;
      const response: IMCDataOkResponse = {
        statusCode: 200,
        contentType: contentType,
        contentLength: 0,
        byteRangeAccessSupported: false,
        contentLoaders: contentLoaders
      };
      return response;
    }
    else {
      contentLoaders.push(new MCMediaHttpContentLoader(this, new MCDownloadRequest(url, proxyRequest.headers)));

      const response: IMCDataOkResponse = {
        statusCode: 200,
        contentType: contentType,
        contentLength: metadata.totalLength !== Number.MAX_SAFE_INTEGER ? metadata.totalLength : undefined,
        byteRangeAccessSupported: metadata.byteRangeAccessSupported,
        contentLoaders: contentLoaders
      }
      return response;
    }
  }

  // http download

  async parseContentRange(request: MCDownloadRequest, responseHeaders: MCDownloadResponseHeaders): Promise<MCRange> {
    try {
      const requestRangeHeader = request.rangeHeader;
      const requestRange = requestRangeHeader ? parseRequestRange(requestRangeHeader) : undefined;
      if ( requestRange ) {
        if ( this.mMetadata!.byteRangeAccessSupported ) {
          throw new Error(`xxx`);
        }

        const contentRangeHeader = responseHeaders['content-range'];
        if ( contentRangeHeader === undefined ) {
          throw new Error(`Response headers missing 'content-range' for request ${JSON.stringify(request)}.`);
        }

        const contentRange = parseResponseContentRange(contentRangeHeader);
        const requestContentRange = generateResponseContentRange(requestRange, this.mMetadata!.totalLength);

        // 确保服务器返回的 range 与请求时一致;
        if ( requestContentRange.rangeStart !== contentRange.rangeStart ||
             requestContentRange.rangeEnd !== contentRange.rangeEnd ||
             requestContentRange.size !== contentRange.size ) {
          throw new Error('Invalid server response: mismatched request range.');  // TODO: http error
        }
        return new MCRange(contentRange.rangeStart, contentRange.rangeEnd + 1 - contentRange.rangeStart);
      }
      return new MCRange(0, this.mMetadata!.totalLength);
    }
    catch (error) {
      throw error as Error;
    }
  }

  createContentInRange(range: MCRange): Promise<IMCMediaContent> {
    return this.createContentAt(range.location, range.length === Number.MAX_SAFE_INTEGER);
  }

  async createContentAt(offset: number, isTemp: boolean): Promise<IMCMediaContent> {
    const content = this.mContentProvider!.createContent(offset, isTemp);
    this.mNodeList.upsertNode(offset, content);
    return content.readwriteRetain();
  }

  async destroyTempContent(content: IMCMediaContent): Promise<void> {
    if ( content.isTemp ) {
      if ( !(await content.destroy()) ) {
        throw new Error(`xxx`);
      }
      const node = this.mNodeList.getNodeBy(content.contentOffset);
      node?.removeContent(content);
    }
  }

  async copyTempContent(content: IMCMediaContent): Promise<void> {
    if ( content.isTemp ) {
      const newContent = this.mContentProvider!.createContent(0);
      this.mNodeList.upsertNode(0, newContent);
      await this.mergeData(newContent, content);
      const metadata: IMCMediaMetadata = {
        contentType: this.mMetadata!.contentType,
        totalLength: newContent.length,
        byteRangeAccessSupported: true,
      };
      this.mMetadata = metadata;
      MCDatabase.saveMediaMetadata(this.id, metadata);
    }
  }

  protected getInstance(): MCMedia {
    return this;
  }

  // 该方法被回调时, 不仅仅当前 media 的读写计数为 0, 所有的 content 的读写计数也都为 0;
  protected onReadwriteZeroReferences(): void {
    this.restructureContents();
  }

  // 重组内容. 合并数据并移除多余内容;
  private async restructureContents(): Promise<void> {
    if ( !this.mFullyTrimmed && this.mMetadata && this.mMetadata.totalLength !== Number.MAX_SAFE_INTEGER ) {
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

          if ( writer?.isTemp ) {
            throw new Error(`试图向临时内容写入数据`);
          }

          if ( writer && reader ) {
            const isMerged = await this.mergeData(writer, reader);
            if ( isMerged ) {
              await reader.destroy();
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

          if (head && head.longestContent?.length === this.mMetadata.totalLength) {
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
      for (let redundant of redundantContents) {

        if ( (redundant.readwriteCount) !== 0 ) {
          MCLogger.warn(MCLogModule.MCMedia, () => `xxx`);
        }

        await redundant.destroy();
        node.removeContent(redundant);
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Destroyed redundant content at offset: ${redundant.contentOffset}.`);
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

    const curRange = new MCRange(writer.contentOffset, writer.length);
    const nextRange = new MCRange(reader.contentOffset, reader.length);
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
      writer.readwriteRetain();
      reader.readwriteRelease();
      try {
        while (position < readRange.max) {
          const len = await reader.readData(position, buffer, buffer.byteLength);
          if (len === 0) break;
          position += await writer.writeData(buffer, len);
        }
        writer.readwriteRelease();
        reader.readwriteRelease();
        await writer.closeWrite();
        await reader.closeRead();

        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Merge completed. Data from reader successfully written to writer.`);
        return true;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during merge: ${error.message}\nStack: ${error.stack}`);
        writer.readwriteRelease();
        reader.readwriteRelease();
        reader.closeRead();
        writer.closeWrite();
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

    if ( totalLength <= 0 ) {
      throw new Error(`The total length must be greater than 0.`);
    }

    const requestRange = parseRequestRange(requestRangeHeader);
    const requestRangeStart = requestRange.rangeStart;
    let requestRangeEnd = requestRange.rangeEnd;
    let requestSuffixLength = requestRange.suffixLength;

    // 检查范围合法性;
    if ( requestRangeStart && requestRangeStart >= totalLength ) {
      throw new Error('Invalid range: range-start exceeds total media length.');
    }
    if ( requestRangeEnd && requestRangeEnd >= totalLength ) {
      requestRangeEnd = totalLength - 1;
    }
    if ( requestSuffixLength && requestSuffixLength > totalLength ) {
      requestSuffixLength = totalLength;
    }

    if (requestRangeStart && requestRangeEnd && requestRangeStart > requestRangeEnd) {
      throw new Error('Invalid range: range-start cannot be greater than range-end.');
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

  private async calculateCompleteness(): Promise<number> {
    if (this.mAssembled) {
      return 1;
    }

    if (!this.mMetadata || this.mMetadata.totalLength === Number.MAX_SAFE_INTEGER || !this.mNodeList.head) {
      return 0;
    }

    let lengthCached = 0;
    let prevMax = 0;
    let node: IMCMediaContentNode | undefined = this.mNodeList.head;
    while (node) {
      const content = node.longestContent;
      if ( content ) {
        const offset = content.contentOffset;
        const length = content.length;
        lengthCached += length;
        if ( prevMax > offset ) lengthCached -= (prevMax - offset);
        prevMax = offset + length;
      }
      node = node.next;
    }
    return lengthCached * 1.0 / this.mMetadata.totalLength;
  }
}