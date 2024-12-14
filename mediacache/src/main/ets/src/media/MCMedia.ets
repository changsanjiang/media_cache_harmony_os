import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";
import { MCMediaContentProvider } from "./MCMediaContentProvider";
import { MCMediaContentNodeList } from "./MCMediaContentNodeList";
import { IMCMediaContentNode } from "../defines/IMCMediaContentNode";
import { MCRange } from "../utils/MCRange";
import { IMCMediaMetadata } from "../defines/IMCMediaMetadata";
import { generateResponseContentRange, parseResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCURL from "../utils/MCURL";
import { MCMediaHttpContentLoader } from "./MCMediaHttpContentLoader";
import { parseRequestRange, toRequestRange, toRequestRangeHeader } from "../defines/IMCHttpRequestRange";
import { MCMediaFileContentLoader } from "./MCMediaFileContentLoader";
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";
import MCDownload from "../utils/MCDownload";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import { IMCDataOkResponse, IMCDataPartialContentResponse, IMCDataResponse } from "../defines/IMCDataResponse";
import { MCDataResponseError } from "../defines/MCDataResponseError";
import { MCAbortSignal } from "../utils/MCAbortController";
import { MCMediaProxyContentLoader } from "./MCMediaProxyContentLoader";
import MCUtils from "../utils/MCUtils";

export class MCMedia extends MCReadwriteReference<MCMedia> implements IMCMedia {
  readonly id: string;
  private mDir: string;
  private mMetadata?: IMCMediaMetadata = undefined;
  private mContentProvider?: MCMediaContentProvider = undefined;
  private mNodeList = new MCMediaContentNodeList();
  private mAssembled = false; // 是否已组合完成, 是否已得到完整内容; 虽然得到了完整内容, 但是文件夹下可能还存在正在读取的冗余数据;
  private mFullyTrimmed = false; // 所有冗余数据都已删除;
  private mProxyHandler?: (requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer> = undefined; // 代理内容;
  private mRestructurePromise?: Promise<void> = undefined;

  /// `id` 中不能包含下划线;
  ///
  /// proxy: 内容需要代理时设置;
  constructor(id: string, dir: string, proxy?: (requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) {
    if (id.includes("_")) {
      throw new Error(`The media ID '${id}' is invalid. Media IDs cannot contain underscores ('_').`);
    }
    super();
    this.id = id;
    this.mDir = dir;
    this.mProxyHandler = proxy;
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
  get isAssembled(): boolean {
    return this.mAssembled;
  }
  // 完成度: [0, 1];
  get completeness(): Promise<number> {
    return this.calculateCompleteness();
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Starting prepare.`);
    try {
      this.mContentProvider = new MCMediaContentProvider(this.id, this.mDir, this.id);
      const metadata = await this.mContentProvider.prepare();
      if (metadata) {
        this.mMetadata = metadata;
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Metadata loaded. ContentType: ${this.mMetadata?.contentType}, TotalLength: ${this.mMetadata?.totalLength}, ByteRangeAccessSupported: ${this.mMetadata?.byteRangeAccessSupported}.`);

        if ( metadata.totalLength == 0 ) { // 空文件
          this.mAssembled = true;
          this.mFullyTrimmed = true;
        }
        else {
          const contents = await this.mContentProvider.loadContents();
          contents?.forEach((content) => this.mNodeList.upsertNode(content.contentOffset, content));
          if (contents && contents.length > 1) {
            await this.restructureContents(); // 重组内容, 删除冗余数据;
          }
        }
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during preparation: ${error.message}\nStack: ${error.stack}`);
      throw error as Error;
    }
  }

  // 探测元数据
  probe(proxyRequest: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCMediaMetadata> {
    if ( this.mMetadata ) {
      return Promise.resolve(this.mMetadata);
    }

    const requestTarget = proxyRequest.requestTarget;
    const headers = proxyRequest.headers;
    const mediaUrl = MCURL.parseUrl(requestTarget);
    const request = new MCDownload.Request(mediaUrl, headers);

    return MCDownload.probe(request, signal).then(async (response) => {
      if ( this.mMetadata ) {
        return this.mMetadata;
      }

      if ( signal?.isAborted === true ) {
        throw signal.reason!
      }

      const statusCode = response.statusCode;
      if ( statusCode !== 200 && statusCode !== 206 ) {
        throw new MCDataResponseError(statusCode, 'xxx');
      }

      if ( this.mProxyHandler && statusCode !== 200 ) {
        throw new MCDataResponseError(400, 'xxx'); // 内容代理仅支持200请求;
      }

      // 探测服务器支持的情况
      // 如果不支持206请求，在未完全下载之前就只创建一个 200 loader

      const headers = response.headers;
      const acceptRangesHeader: string | undefined = headers['accept-ranges'];
      const contentRangeHeader: string | undefined = headers['content-range'];
      const contentTypeHeader: string | undefined = headers['content-type'];
      const contentLengthHeader: string | undefined = headers['content-length'];

      const contentType = contentTypeHeader || 'application/octet-stream';
      const byteRangeAccessSupported = this.mProxyHandler ? false : statusCode === 206 || acceptRangesHeader === 'bytes';

      /// - 情况1: 当内容需要代理时, 最终的数据长度只有在生成代理内容后才能确定, 这里需要暂时设置为 Number.MAX_SAFE_INTEGER;
      /// - 情况2: 有些服务器不会返回 contentLengthHeader, 这里需要暂时设置 Number.MAX_SAFE_INTEGER;
      const contentLength = this.mProxyHandler ? Number.MAX_SAFE_INTEGER : (contentLengthHeader ? parseInt(contentLengthHeader, 10) : Number.MAX_SAFE_INTEGER);
      const contentRange = contentRangeHeader ? parseResponseContentRange(contentRangeHeader) : undefined;
      const totalLength = contentRange ? contentRange.size : contentLength;

      const metadata: IMCMediaMetadata = {
        contentType: contentType,
        totalLength: totalLength,
        byteRangeAccessSupported: byteRangeAccessSupported
      };
      this.mMetadata = metadata;
      this.mContentProvider?.saveMetadata(metadata);
      return metadata;
    });
  }

  fetch(request: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCDataResponse> {
    return this.probe(request, signal).then(() => this.resolve(request, signal)).catch((error: Error) => {
      if ( !(error instanceof MCDataResponseError) ) {
        throw error;
      }

      const response: IMCDataResponse = {
        statusCode: error.statusCode
      };
      return response;
    });
  }

  async readAllData(): Promise<ArrayBuffer | undefined> {
    if ( this.mAssembled ) {
      if ( this.mRestructurePromise ) {
        await this.mRestructurePromise;
      }

      let buffer: ArrayBuffer | undefined = undefined;
      let node = this.mNodeList.head;
      let offset = 0;
      while (node) {
        const content = node.longestContent;
        if ( content ) {
          const contentOffset = content.contentOffset;
          const contentLength = content.length;
          const readLen = (contentOffset + contentLength) - offset;
          if ( readLen > 0 ) {
            const reader = content.createReader();
            const data = new ArrayBuffer(readLen);
            await reader.readData(offset, data, readLen);
            buffer = buffer ? MCUtils.mergeArrayBuffers(buffer, data) : data;
            await reader.close();
            offset += readLen;
          }
        }
        node = node.next;
      }
      return buffer;
    }
    return undefined;
  }

  private async resolve(proxyRequest: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCDataResponse> {
    if ( this.mRestructurePromise ) {
      await this.mRestructurePromise;
    }

    if ( signal && signal.isAborted ) {
      throw signal.reason!
    }

    const url = MCURL.parseUrl(proxyRequest.requestTarget);
    if (!url) {
      throw new MCDataResponseError(400, "Failed to restore URL from the provided request.");
    }
    const metadata = this.mMetadata!;
    const contentType = metadata.contentType;
    const totalLength = metadata.totalLength;
    const contentLoaders: IMCMediaContentLoader[] = [];
    if (metadata.byteRangeAccessSupported && metadata.totalLength > 0) {
      const requestRangeHeader = proxyRequest.headers?.['range'];
      const contentRange = requestRangeHeader ? this.generateContentRange(requestRangeHeader, totalLength) : new MCRange(0, totalLength);

      let readRange = new MCRange(contentRange.location, contentRange.length);
      let curNode: IMCMediaContentNode | undefined = this.mNodeList.findClosestLeftNode(readRange.location) ?? this.mNodeList.head;

      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Read range parsed as: ${JSON.stringify(readRange)}`);

      while (curNode) {
        // 获取当前长度最长的内容
        const content = curNode.longestContent!; // 每个节点中都包含至少一个内容;
        // 可读取的范围
        const readableRange = new MCRange(content.contentOffset, content.length);
        const intersection = readRange.intersection(readableRange);
        // 如果存在交集
        if ( intersection ) {
          // 获取左侧未下载的部分
          if ( intersection.location > readRange.location ) {
            const leftRange = new MCRange(readRange.location, intersection.location - readRange.location);
            const leftRequest = new MCDownloadRequest(url, proxyRequest.headers);
            leftRequest.setHeader('range', toRequestRangeHeader(toRequestRange(leftRange)));
            contentLoaders.push(new MCMediaHttpContentLoader(this, leftRequest));
          }
          contentLoaders.push(new MCMediaFileContentLoader(content, intersection));
          readRange = new MCRange(intersection.max, readRange.max - intersection.max);
        }
        if ( readRange.length === 0 || readableRange.location > readRange.max ) {
          break;
        }
        curNode = curNode.next;
      }

      // 剩余未下载的部分;
      if (readRange.length !== 0) {
        const request = new MCDownloadRequest(url, proxyRequest.headers);
        request.setHeader('range', toRequestRangeHeader(toRequestRange(readRange)));
        contentLoaders.push(new MCMediaHttpContentLoader(this,request));
      }

      // 206
      if ( requestRangeHeader ) {
        const response: IMCDataPartialContentResponse = {
          statusCode: 206,
          contentType: contentType,
          contentRange: contentRange,
          totalLength: totalLength,
          contentLoaders: contentLoaders
        };
        return response;
      }

      // 200
      const response: IMCDataOkResponse = {
        statusCode: 200,
        contentType: contentType,
        contentLength: totalLength,
        byteRangeAccessSupported: true,
        contentLoaders: contentLoaders
      };
      return response;
    }
    else if (metadata.totalLength === 0) { // empty content;
      const response: IMCDataOkResponse = {
        statusCode: 200,
        contentType: contentType,
        contentLength: 0,
        contentLoaders: contentLoaders
      };
      return response;
    }
    else {
      if ( !this.mProxyHandler ) {
        contentLoaders.push(new MCMediaHttpContentLoader(this, new MCDownloadRequest(url, proxyRequest.headers)));
      }
      else {
        contentLoaders.push(new MCMediaProxyContentLoader(this, new MCDownloadRequest(url, proxyRequest.headers)));
      }

      const contentLength = metadata.totalLength !== Number.MAX_SAFE_INTEGER ? metadata.totalLength : undefined;
      const response: IMCDataOkResponse = {
        statusCode: 200,
        contentType: contentType,
        contentLength: contentLength,
        chunked: contentLength === undefined,
        byteRangeAccessSupported: metadata.byteRangeAccessSupported,
        contentLoaders: contentLoaders
      }
      return response;
    }
  }

  // 解析内容范围
  // 如果是 206 请求, response 必须指定 content-range 字段;
  // 如果是 200 请求: 依赖于 content-length 字段, 有些服务器可能不返回这个字段;
  //
  // 200 或 206 => {start, length};
  // 当 200 请求的响应未指定 content-length 字段时返回 {0, Number.MAX_SAFE_INTEGER}
  parseContentRange(request: MCDownloadRequest, responseHeaders: MCDownloadResponseHeaders): MCRange {
    try {
      const requestRangeHeader = request.rangeHeader;
      const requestRange = requestRangeHeader ? parseRequestRange(requestRangeHeader) : undefined;
      if ( requestRange ) {
        if ( !this.mMetadata!.byteRangeAccessSupported ) {
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
  // 当范围是 {0, Number.MAX_SAFE_INTEGER} 返回临时 content; 下载完成后通过 copyTempContent 保存到正式目录;
  createContentInRange(range: MCRange): Promise<IMCMediaContent> {
    return this.createContentAt(range.location, range.length === Number.MAX_SAFE_INTEGER);
  }
  // 当范围是 {0, Number.MAX_SAFE_INTEGER} 需要创建临时 content; 下载完成后通过 copyTempContent 保存到正式目录;
  async createContentAt(offset: number, isTemp: boolean): Promise<IMCMediaContent> {
    if ( this.mRestructurePromise ) {
      await this.mRestructurePromise;
    }

    const content = this.mContentProvider!.createContent(offset, isTemp);
    this.mNodeList.upsertNode(offset, content);
    return content;
  }

  async destroyTempContent(content: IMCMediaContent): Promise<void> {
    if ( this.mRestructurePromise ) {
      await this.mRestructurePromise;
    }

    if ( content.isTemp ) {
      await content.destroy();
      const node = this.mNodeList.getNodeBy(content.contentOffset);
      node?.removeContent(content);
    }
  }
  async copyTempContent(content: IMCMediaContent): Promise<void> {
    if ( this.mRestructurePromise ) {
      await this.mRestructurePromise;
    }

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
      this.mContentProvider?.saveMetadata(metadata);
    }
  }

  // 生成代理内容;
  applyProxy(requestUrl: string, currentUrl: string, contentData: ArrayBuffer): Promise<ArrayBuffer> {
    return this.mProxyHandler!(requestUrl, currentUrl, contentData);
  }

  protected getInstance(): MCMedia {
    return this;
  }

  // 该方法被回调时, 不仅仅当前 media 的读写计数为 0, 所有的 content 的读写计数也都为 0;
  protected onReadwriteZeroReferences(): void {
    if ( !this.mRestructurePromise ) this.mRestructurePromise = new Promise(async (resolve) => {
      await this.restructureContents();
      this.mRestructurePromise = undefined;
      resolve();
    });
  }

  // 重组内容. 合并数据并移除多余内容;
  private async restructureContents(): Promise<void> {
    if ( !this.mFullyTrimmed && this.mMetadata && this.mMetadata.totalLength !== Number.MAX_SAFE_INTEGER ) {
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Starting restructureContents.`);

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
        }

        if (head && head.longestContent?.length === this.mMetadata.totalLength) {
          this.mAssembled = true;
          this.mFullyTrimmed = this.mNodeList.count === 1 && head.numberOfContents === 1;
          MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Content restructuring completed. Assembled: ${this.mAssembled}, FullyTrimmed: ${this.mFullyTrimmed}.`);
        }
      }
      catch (error) {
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
        await redundant.destroy();
        node.removeContent(redundant);
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Destroyed redundant content at offset: ${redundant.contentOffset}.`);
      }
    }
  }

  // 合并数据; 被合并后返回 true;
  // writer.contentOffset <= reader.contentOffset;
  private async mergeData(writerContent: IMCMediaContent, readerContent: IMCMediaContent): Promise<boolean> {
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Attempting to merge data between writer at offset ${writerContent.contentOffset} and reader at offset ${readerContent.contentOffset}.`);
    if ( writerContent.contentOffset > readerContent.contentOffset ) {
      // writer的内容偏移量 必须在 reader 的前面, 这样才能在存在交集时合并数据;
      const errorMsg = `Invalid offsets: writer offset (${writerContent.contentOffset}) must be less than or equal to reader offset (${readerContent.contentOffset}).`;
      MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: ${errorMsg}`);
      throw new Error(errorMsg);
    }

    const curRange = new MCRange(writerContent.contentOffset, writerContent.length);
    const nextRange = new MCRange(readerContent.contentOffset, readerContent.length);
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
      let writer = writerContent.createWriter();
      let reader = readerContent.createReader();
      try {
        while (position < readRange.max) {
          const len = await reader.readData(position, buffer, buffer.byteLength);
          if (len === 0) break;
          position += await writer.writeData(buffer, len);
        }
        await reader.close();
        await writer.close();

        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Merge completed. Data from reader successfully written to writer.`);
        return true;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during merge: ${error.message}\nStack: ${error.stack}`);
        reader.close();
        writer.close();
        throw error as Error;
      }
    }
    MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Ranges are not intersecting or contiguous. No merge performed.`);
    return false;
  }

  private generateContentRange(requestRangeHeader: string, totalLength: number): MCRange {
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

  // private printDebugInfo() {
  //   setTimeout(() => {
  //     console.log(`AAAA: media.readwriteCount=${this.readwriteCount}`);
  //     this.printDebugInfo();
  //   }, 10000);
  // }
}