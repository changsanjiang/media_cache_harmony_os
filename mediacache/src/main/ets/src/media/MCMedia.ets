import { IMCMedia, MCMediaCopyBehaviorOptions } from "../defines/IMCMedia";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { IMCMediaContent, IMCMediaContentReader, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";
import { MCMediaContentProvider } from "./MCMediaContentProvider";
import { MCMediaContentNodeList } from "./MCMediaContentNodeList";
import { IMCMediaContentNode } from "../defines/IMCMediaContentNode";
import { MCRange } from "../utils/MCRange";
import { IMCMediaMetadata } from "../defines/IMCMediaMetadata";
import { generateResponseContentRange, parseResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import { MCProxyUtils } from "../utils/MCProxyUtils";
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
import { MCMediaKind } from "../defines/MCMediaKind";

export class MCMedia extends MCReadwriteReference<MCMedia> implements IMCMedia {
  readonly id: string;
  readonly mediaKind: MCMediaKind;
  private mDir: string;
  private mAbortSignal: MCAbortSignal;
  private mMetadata?: IMCMediaMetadata = undefined;
  private mMetadataFileSize = 0;
  private mContentProvider: MCMediaContentProvider;
  private mNodeList = new MCMediaContentNodeList();
  private mAssembled = false; // 是否已组合完成, 是否已得到完整内容; 虽然得到了完整内容, 但是文件夹下可能还存在正在读取的冗余数据;
  private mFullyTrimmed = false; // 已组合完成并且所有冗余数据都已删除;
  private mProxyHandler?: (requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer> = undefined; // 代理内容;
  private mRestructurePromise?: Promise<void> = undefined;

  /// `id` 中不能包含下划线;
  ///
  /// proxy: 内容需要代理时设置;
  constructor(id: string, mediaKind: MCMediaKind, dir: string, abortSignal: MCAbortSignal, proxy?: (requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) {
    if (id.includes("_")) {
      throw new Error(`The media ID '${id}' is invalid. Media IDs cannot contain underscores ('_').`);
    }
    super();
    this.id = id;
    this.mediaKind = mediaKind;
    this.mDir = dir;
    this.mAbortSignal = abortSignal;
    this.mProxyHandler = proxy;
    this.mContentProvider = new MCMediaContentProvider(this.id, this.mDir);
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${id}]: MCMedia instance created with dir ${dir}.`);
  }

  get abortSignal(): MCAbortSignal {
    return this.mAbortSignal;
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
  get currentCachedSize(): number {
    let len = this.mMetadataFileSize;
    let node: IMCMediaContentNode | undefined = this.mNodeList.head;
    while (node) {
      len += node.lengthOfAllContents;
      node = node.next;
    }
    return len;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Starting prepare.`);
    try {
      const entries = await this.mContentProvider.prepare();
      this.checkAbortSignal(this.mAbortSignal);

      if (entries) {
        this.mMetadataFileSize = entries[0];
        this.mMetadata = entries[1];
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Metadata successfully loaded. ContentType: ${this.mMetadata?.contentType}, TotalLength: ${this.mMetadata?.totalLength}, ByteRangeAccessSupported: ${this.mMetadata?.byteRangeAccessSupported}.`);

        if ( this.mMetadata.totalLength == 0 ) { // 空文件
          this.mAssembled = true;
          this.mFullyTrimmed = true;
          MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Detected empty file. Marked as assembled and fully trimmed.`);
        }
        else {
          const contents = await this.mContentProvider.loadContents();
          this.checkAbortSignal(this.mAbortSignal);
          MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Loaded ${contents?.length || 0} content blocks from storage.`);

          contents?.forEach((content) => this.mNodeList.upsertToNode(content.contentOffset, content));
          if (contents && contents.length > 0) {
            if ( contents.length === 1 ) {
              if ( contents[0].length === this.mMetadata.totalLength ) {
                this.mAssembled = true;
                this.mFullyTrimmed = true;
                MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Single content block matches total length. Marked as assembled and fully trimmed.`
                );
              }
            }
            else {
              MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Multiple content blocks detected (${contents.length}). Starting restructuring to remove redundant data.`);
              await this.restructureContents(); // 重组内容, 删除冗余数据;
            }
          }
        }
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during preparation: ${error.message}. Stack trace: ${error.stack}`);
      throw error as Error;
    }
  }

  // 探测元数据
  probe(proxyRequest: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCMediaMetadata> {
    if ( this.mMetadata ) {
      return Promise.resolve(this.mMetadata);
    }

    const proxyPath = proxyRequest.requestTarget;
    const headers = proxyRequest.headers;
    const mediaUrl = MCProxyUtils.parseTargetUrl(proxyPath);
    const request = new MCDownloadRequest(mediaUrl, headers);

    return MCDownload.probe(request, signal).then(async (response) => {
      if ( this.mMetadata ) {
        return this.mMetadata;
      }

      this.checkAbortSignal(signal);

      const statusCode = response.statusCode;
      if ( statusCode !== 200 && statusCode !== 206 ) {
        throw new MCDataResponseError(statusCode, `Unexpected HTTP status code: ${statusCode}`);
      }

      if ( this.mProxyHandler && statusCode !== 200 ) {
        throw new MCDataResponseError(500, 'Content proxy mode requires HTTP status code 200'); // 内容代理仅支持200请求;
      }

      // 探测服务器支持的情况
      // 如果不支持206请求，在未完全下载之前就只创建一个 200 loader

      const headers = response.headers;
      const acceptRangesHeader: string | undefined = headers['accept-ranges'];
      const contentRangeHeader: string | undefined = headers['content-range'];
      const contentTypeHeader: string | undefined = headers['content-type'];
      const contentLengthHeader: string | undefined = headers['content-length'];

      const contentType = contentTypeHeader || 'application/octet-stream';
      const byteRangeAccessSupported = !this.mProxyHandler && (statusCode === 206 || acceptRangesHeader === 'bytes');

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
      this.mContentProvider.saveMetadata(metadata);
      return metadata;
    });
  }

  fetch(request: IMCDataRequest, clientId: number, signal?: MCAbortSignal): Promise<IMCDataResponse> {
    return this.probe(request, signal).then(() => this.resolve(request, clientId, signal)).catch((error: Error) => {
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
    if ( this.mRestructurePromise ) {
      await this.mRestructurePromise;
    }

    this.checkAbortSignal(this.mAbortSignal);

    const completeContent = this.mNodeList.head?.longestContent;
    if ( completeContent && this.mAssembled ) {
      const reader = completeContent.createReader();
      const data = new ArrayBuffer(completeContent.length);
      await reader.readData(0, data, completeContent.length);
      await reader.close();
      return data;
    }

    const completeness = await this.completeness;
    if ( completeness == 1.0 ) {
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

  private async resolve(proxyRequest: IMCDataRequest, clientId: number, signal?: MCAbortSignal): Promise<IMCDataResponse> {
    if ( this.mRestructurePromise ) {
      await this.mRestructurePromise;
    }

    this.checkAbortSignal(signal);

    const url = MCProxyUtils.parseTargetUrl(proxyRequest.requestTarget);
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
            contentLoaders.push(new MCMediaHttpContentLoader(clientId, contentLoaders.length, this, leftRequest));
          }
          contentLoaders.push(new MCMediaFileContentLoader(clientId, contentLoaders.length, content, intersection));
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
        contentLoaders.push(new MCMediaHttpContentLoader(clientId, contentLoaders.length, this,request));
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
        contentLoaders.push(new MCMediaHttpContentLoader(clientId, contentLoaders.length, this, new MCDownloadRequest(url, proxyRequest.headers)));
      }
      else {
        contentLoaders.push(new MCMediaProxyContentLoader(clientId, contentLoaders.length, this, new MCDownloadRequest(url, proxyRequest.headers)));
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

  async copyToDirectory(targetDir: string, options?: MCMediaCopyBehaviorOptions): Promise<void> {
    await this.ensureReadyForCopy();

    // 将元数据复制到指定目录
    await this.mContentProvider.copyMetadataToDirectory(targetDir, options?.conflictStrategy);
    // 将媒体数据复制到指定目录

    // 执行到这里时虽然此时的完整度是1, 但可能还未将所有的content块组合成完整文件;
    // 如果已存在完整文件(this.mAssembled == true), 则直接复制到指定目录,
    // 否则创建一个新的 finalContent, 遍历node把数据写入到finalContent中, 再复制到指定目录;

    if ( this.mMetadata && this.mMetadata.totalLength > 0 ) {
      const finalContent = await this.getOrAssembleFinalContent();
      await finalContent.copyToDirectory(targetDir, options?.conflictStrategy);
    }
  }

  private async ensureReadyForCopy(): Promise<void> {
    if (this.mRestructurePromise) {
      await this.mRestructurePromise;
    }

    this.checkAbortSignal(this.mAbortSignal);

    const completeness = await this.completeness;
    if (completeness !== 1) {
      throw new Error(`Copy failed: Media local cache is incomplete and cannot be copied.`);
    }
  }

  private async getOrAssembleFinalContent(): Promise<IMCMediaContent> {
    const headContent = this.mNodeList.head?.longestContent;
    if ( headContent && this.mAssembled ) {
      return headContent;
    }

    return await this.assembleFinalContent();
  }

  // 组装 finalContent, 出现断层时会抛出异常
  private async assembleFinalContent(): Promise<IMCMediaContent> {
    const finalContent = this.mContentProvider.createContent(0);
    const writerContent = finalContent;
    const writer = writerContent.createWriter();

    const capacity = 4 * 1024 * 1024;
    const buffer = new ArrayBuffer(capacity);

    let node = this.mNodeList.head;
    try {
      while ( node ) {
        const readerContent = node.longestContent;
        if ( readerContent ) {
          const curRange = new MCRange(writerContent.contentOffset, writerContent.length);
          const nextRange = new MCRange(readerContent.contentOffset, readerContent.length);

          if ( curRange.contains(nextRange) ) {
            node = node.next;
            continue;
          }

          // 出现断层时抛出异常
          if ( curRange.max !== nextRange.location && !curRange.isIntersecting(nextRange) ) {
            throw new Error(`Copy failed: Detected inconsistency in local media cache data. Content ranges are misaligned or overlapping incorrectly.`);
          }

          const readRange = new MCRange(curRange.max, nextRange.max - curRange.max);
          const reader = readerContent.createReader();
          await this.transferContentData(writer, reader, readRange, buffer, false, true);
        }
        node = node.next;
      }
    }
    finally {
      writer.close();
    }
    return finalContent;
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
          throw new Error(`Byte range access is not supported for the requested content. Request range: ${JSON.stringify(requestRange)}, Metadata: ${JSON.stringify(this.mMetadata)}`);
        }

        const contentRangeHeader = responseHeaders['content-range'];
        if ( contentRangeHeader === undefined ) {
          throw new Error(`Response headers missing 'content-range' for the given request. Request: ${JSON.stringify(request)}, Response Headers: ${JSON.stringify(responseHeaders)}`);
        }

        const contentRange = parseResponseContentRange(contentRangeHeader);
        const requestContentRange = generateResponseContentRange(requestRange, this.mMetadata!.totalLength);

        // 确保服务器返回的 range 与请求时一致;
        if ( requestContentRange.rangeStart !== contentRange.rangeStart ||
             requestContentRange.rangeEnd !== contentRange.rangeEnd ||
             requestContentRange.size !== contentRange.size ) {
          throw new Error(`Invalid server response: Mismatched content range. Expected: ${JSON.stringify(requestContentRange)}, Actual: ${JSON.stringify(contentRange)}, Request: ${JSON.stringify(request)}, Metadata: ${JSON.stringify(this.mMetadata)}`);
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
  createContentByRange(range: MCRange): Promise<IMCMediaContent> {
    return this.createContentAt(range.location, range.length === Number.MAX_SAFE_INTEGER);
  }
  // 当范围是 {0, Number.MAX_SAFE_INTEGER} 需要创建临时 content; 下载完成后通过 copyTempContent 保存到正式目录;
  async createContentAt(offset: number, isTemp: boolean): Promise<IMCMediaContent> {
    if ( this.mRestructurePromise ) {
      await this.mRestructurePromise;
    }

    const content = this.mContentProvider!.createContent(offset, isTemp);
    this.mNodeList.upsertToNode(offset, content);
    return content;
  }

  // 生成代理内容;
  // 原始 m3u8 文件中记录着的各个媒体片段, 它们都需要代理请求, 通过该方法将原始 m3u8 的文件内容替换成代理内容;
  applyProxy(requestUrl: string, currentUrl: string, contentData: ArrayBuffer): Promise<ArrayBuffer> {
    return this.mProxyHandler!(requestUrl, currentUrl, contentData);
  }

  /** 销毁临时内容; */
  async destroy(content: IMCMediaContent): Promise<void> {
    if ( content.isTemp ) {
      await content.destroy();
      const node = this.mNodeList.getNodeBy(content.contentOffset);
      node?.removeContent(content);
    }
  }

  /** 交付最终内容; 临时内容转为正式内容; */
  async finalize(content: IMCMediaContent): Promise<void> {
    if ( content.isTemp ) {
      content.finalize();
      const metadata: IMCMediaMetadata = {
        contentType: this.mMetadata!.contentType,
        totalLength: content.length,
        byteRangeAccessSupported: true,
      };
      this.mMetadata = metadata;
      this.mContentProvider.saveMetadata(metadata);
    }
  }

  protected getInstance(): MCMedia {
    return this;
  }

  // 该方法被回调时, 不仅仅当前 media 的读写计数为 0, 所有的 content 的读写计数也都为 0;
  protected async onReadwriteZeroReferences(): Promise<void> {
    if ( !this.mRestructurePromise ) {
      this.mRestructurePromise = this.restructureContents();
      try {
        await this.mRestructurePromise;
      }
      finally {
        this.mRestructurePromise = undefined;
      }
    }
  }

  // 重组内容. 合并数据并移除多余内容;
  private async restructureContents(): Promise<void> {
    if ( !this.mFullyTrimmed && this.mMetadata && this.mMetadata.totalLength !== Number.MAX_SAFE_INTEGER ) {
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Starting restructureContents.`);
      this.checkAbortSignal(this.mAbortSignal);

      const capacity = 4 * 1024 * 1024;
      const buffer = new ArrayBuffer(capacity);

      try {
        const head = this.mNodeList.head;
        let curNode = head;

        while ( curNode ) {
          // 清理当前节点冗余内容
          if ( curNode.numberOfContents > 1 ) {
            await this.trimRedundantContents(curNode);
          }

          const nextNode = curNode.next;
          if ( !nextNode ) break;  // break;

          // 清理下一个节点冗余内容
          if ( nextNode.numberOfContents > 1 ) {
            await this.trimRedundantContents(nextNode);
          }

          const writerContent = curNode.longestContent;
          const readerContent = nextNode.longestContent;

          if ( writerContent?.isTemp ) {
            throw new Error(`Attempted to write data into a temporary content file. MediaId: ${this.id}, Writer: ${JSON.stringify(writerContent)}, Reader: ${JSON.stringify(readerContent)}`);
          }

          if ( writerContent && readerContent ) {
            const isMerged = await this.mergeData(writerContent, readerContent, buffer);
            if ( isMerged ) {
              await readerContent.destroy();
              nextNode.removeContent(readerContent);

              MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Merged content from nextNode into currentNode.`);

              if ( nextNode.numberOfContents == 0 ) {
                this.mNodeList.removeNode(nextNode);
                MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Removed empty nextNode.`);
              }
            }
          }

          curNode = curNode.next;
        }

        if ( head && head.longestContent?.length === this.mMetadata.totalLength ) {
          this.mAssembled = true;
          this.mFullyTrimmed = this.mNodeList.count === 1 && head.numberOfContents === 1;
          MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Content restructuring completed. Assembled: ${this.mAssembled}, FullyTrimmed: ${this.mFullyTrimmed}.`);
        }
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during content restructuring: ${error.message}. Stack trace: ${error.stack}`);
        throw error as Error;
      }
    }
  }

  private async trimRedundantContents(node: IMCMediaContentNode): Promise<void> {
    if ( node.numberOfContents > 1 ) {
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Trimming redundant contents for node at offset: ${node.placement}.`);

      // 同一段位置可能存在多个文件
      // 保留最长的内容, 删除其他多余的无用的content
      const longestContent = node.longestContent!;
      const redundantContents = node.filterContents((content) => content !== longestContent);
      for (let redundant of redundantContents) {
        await redundant.destroy();
        this.checkAbortSignal(this.mAbortSignal);
        node.removeContent(redundant);
        MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Destroyed redundant content at offset: ${redundant.contentOffset}.`);
      }
    }
  }

  // 尝试将 readerContent 中的数据合并到 writerContent 中, 被合并后返回 true
  // @param buffer 可复用的缓冲区（ArrayBuffer）
  private async mergeData(writerContent: IMCMediaContent, readerContent: IMCMediaContent, buffer: ArrayBuffer): Promise<boolean> {
    MCLogger.info(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Attempting to merge data. Writer range: offset ${writerContent.contentOffset} to ${writerContent.contentOffset + writerContent.length}, Reader range: offset ${readerContent.contentOffset} to ${readerContent.contentOffset + readerContent.length}.`);
    if ( writerContent.contentOffset > readerContent.contentOffset ) {
      // Writer 必须在 Reader 之前或相同位置开始, 这样才能在存在交集时合并数据;
      const errorMsg = `Invalid offsets: writer offset (${writerContent.contentOffset}) must be less than or equal to reader offset (${readerContent.contentOffset}).`;
      MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: ${errorMsg}`);
      throw new Error(errorMsg);
    }

    const curRange = new MCRange(writerContent.contentOffset, writerContent.length);
    const nextRange = new MCRange(readerContent.contentOffset, readerContent.length);
    // 已完全包含 Reader 数据: 无需合并
    // return YES;
    if ( curRange.contains(nextRange) ) {
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Writer range fully contains reader range. Skipping merge.`);
      return true;
    }

    // 检查是否相邻或相交
    const isAdjacent = curRange.max === nextRange.location;
    const isIntersecting = curRange.isIntersecting(nextRange);

    // 无交集: 不合并
    if (!isAdjacent && !isIntersecting) {
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Merge skipped. Ranges are neither contiguous nor overlapping. Writer max: ${curRange.max}, Reader start: ${nextRange.location}.`);
      return false;
    }

    // 相邻或交叉: 合并尾部缺失的数据
    // return YES;
    const readRange = new MCRange(curRange.max, nextRange.max - curRange.max);
    const reader = readerContent.createReader();
    const writer = writerContent.createWriter();
    try {
      await this.transferContentData(writer, reader, readRange, buffer);
      MCLogger.debug(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Merge completed successfully.`);
      return true;
    }
    catch (err) {
      MCLogger.error(MCLogModule.MCMedia, () => `[mediaId: ${this.id}]: Error during merge: ${(err as Error).message}`);
      throw err as Error;
    }
  }

  /**
   * 将 reader 中指定范围的数据拷贝到 writer。
   * @param writer 已打开的内容写入器
   * @param reader 已打开的内容读取器
   * @param readRange 要拷贝的数据范围
   * @param buffer 可复用的缓冲区（ArrayBuffer）
   * @param closeWriter 是否在结束时关闭 writer（默认 true）
   * @param closeReader 是否在结束时关闭 reader（默认 true）
   * @throws 如果数据未完整读取到预期位置，则抛出异常
   */
  private async transferContentData(
    writer: IMCMediaContentWriter,
    reader: IMCMediaContentReader,
    readRange: MCRange,
    buffer: ArrayBuffer,
    closeWriter: boolean = true,
    closeReader: boolean = true,
  ): Promise<void> {
    const startOffset = readRange.location;
    const endOffset = readRange.max;

    let position = startOffset;
    try {
      while ( position < endOffset ) {
        const len = await reader.readData(position, buffer, buffer.byteLength);
        if ( len === 0 && position < endOffset ) {
          throw new Error(`Data transfer failed: Unexpected EOF before reaching ${endOffset}.`);
        }
        position += await writer.writeData(buffer, len);
      }
    }
    finally {
      if ( closeWriter ) await writer.close();
      if ( closeReader ) await reader.close();
    }
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
      return 1.0;
    }

    if (!this.mMetadata || this.mMetadata.totalLength === Number.MAX_SAFE_INTEGER || !this.mNodeList.head) {
      return 0.0;
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
    return lengthCached / this.mMetadata.totalLength;
  }

  private checkAbortSignal(signal: MCAbortSignal | undefined) {
    if ( signal && signal.isAborted ) {
      throw signal.reason as Error;
    }
  }

  // private printDebugInfo() {
  //   setTimeout(() => {
  //     console.log(`AAAA: media.readwriteCount=${this.readwriteCount}`);
  //     this.printDebugInfo();
  //   }, 10000);
  // }
}