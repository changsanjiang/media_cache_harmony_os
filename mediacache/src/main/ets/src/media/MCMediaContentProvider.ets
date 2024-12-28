import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCMediaContent } from "./MCMediaContent";
import { fileIo } from "@kit.CoreFileKit";
import { IMCMediaMetadata } from "../defines/IMCMediaMetadata";
import { MCUtils } from "../../../../../Index";
import { JSON } from "@kit.ArkTS";

export class MCMediaContentProvider {
  private mMediaId: string;
  private mDir: string;
  private mMetadataFileNamePrefix: string;
  private mContentFileNamePrefix: string; // file name prefix of content;
  private mContentFileSequence = 0; // file sequence number of content;

  constructor(mediaId: string, dir: string) {
    this.mMediaId = mediaId;
    this.mDir = dir;
    this.mMetadataFileNamePrefix = "m";
    this.mContentFileNamePrefix = "c";
  }

  async prepare(): Promise<[number, IMCMediaMetadata] | undefined> {
    const exists = await fileIo.access(this.mDir, fileIo.AccessModeType.EXIST);
    if ( !exists ) {
      await fileIo.mkdir(this.mDir, true);
      return undefined;
    }

    const entries = await this.loadMetadata();
    if ( !entries ) {
      return undefined;
    }

    const metadata = entries[1];
    if ( metadata.totalLength === Number.MAX_SAFE_INTEGER ) {
      // 这些文件需要删除(元数据未就绪之前, 无法确定内容完整性);
      try {
        const fileNames = await fileIo.listFile(this.mDir);
        const prefix = `${this.mContentFileNamePrefix}_`;
        const unavailableContents = fileNames.length > 0 ? fileNames.filter((fileName) => fileName.startsWith(prefix)) : undefined;
        if ( unavailableContents ) {
          for (let fileName of unavailableContents) {
            const filePath = `${this.mDir}/${fileName}`;
            await fileIo.unlink(filePath);
          }
        }
      }
      catch (error) { }
    }
    return entries;
  }

  /** 返回文件大小和元数据; */
  private async loadMetadata(): Promise<[number, IMCMediaMetadata] | undefined> {
    try {
      const fileName = this.generateMetadataFileName();
      const filePath = `${this.mDir}/${fileName}`;
      const exists = await fileIo.access(filePath, fileIo.AccessModeType.EXIST);
      if ( exists ) {
        const content = await fileIo.readText(filePath, { encoding: 'utf-8' });
        const record = JSON.parse(content) as Record<string, string>;
        const checksum = record['checksum'];
        const jsonStr = record['data'];
        const calculatedChecksum = await MCUtils.hash(jsonStr);
        if ( checksum === calculatedChecksum ) {
          const fileSize = (await fileIo.stat(filePath)).size;
          return [fileSize, JSON.parse(jsonStr) as IMCMediaMetadata];
        }
      }
    }
    catch (error) { }
    return undefined;
  }

  /** 写入成功后返回文件大小; */
  async saveMetadata(metadata: IMCMediaMetadata): Promise<number> {
    try {
      const jsonStr = JSON.stringify(metadata);
      const checksum = await MCUtils.hash(jsonStr);
      const record: Record<string, string> = {
        'checksum': checksum,
        'data': jsonStr
      };
      const content = JSON.stringify(record);
      const buffer = MCUtils.stringToBuffer(content);
      const fileName = this.generateMetadataFileName();
      const filePath = `${this.mDir}/${fileName}`;
      const file = await fileIo.open(filePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC | fileIo.OpenMode.CREATE);
      await fileIo.write(file.fd, buffer);
      return buffer.byteLength;
    }
    catch (error) { }
    return 0;
  }

  /** 加载目录下缓存的媒体内容; */
  async loadContents(): Promise<IMCMediaContent[] | undefined> {
    const fileNames = await fileIo.listFile(this.mDir);
    const prefix = `${this.mContentFileNamePrefix}_`;
    const contentFileNames = fileNames.length > 0 ? fileNames.filter((fileName) => fileName.startsWith(prefix)) : undefined;
    return contentFileNames && contentFileNames.length > 0 ? Promise.all(contentFileNames.map(async (fileName) => {
      const filePath = `${this.mDir}/${fileName}`;
      const fileSize = (await fileIo.stat(filePath)).size;
      const props = this.getContentOffsetAndSequence(fileName);
      const contentOffset = parseInt(props[0], 10);
      const sequence = parseInt(props[1], 10);
      if ( this.mContentFileSequence < sequence ) this.mContentFileSequence = sequence;
      return new MCMediaContent(this.mMediaId, contentOffset, filePath, fileSize);
    })) : undefined;
  }

  createContent(contentOffset: number, temp: boolean = false): IMCMediaContent {
    const sequence = this.mContentFileSequence + 1;
    this.mContentFileSequence = sequence;
    const fileName = this.generateContentFileName(contentOffset, sequence);
    const filePath = `${this.mDir}/${fileName}`;
    const content = new MCMediaContent(this.mMediaId, contentOffset, filePath, 0, temp);
    return content;
  }

  /** file name format: `prefix_mediaId_contentOffset_sequence`; */
  private generateContentFileName(contentOffset: number, sequence: number): string {
    return `${this.mContentFileNamePrefix}_${this.mMediaId}_${contentOffset}_${sequence}`;
  }

  /** file name format: `prefix_mediaId`; */
  private generateMetadataFileName(): string {
    return `${this.mMetadataFileNamePrefix}_${this.mMediaId}`;
  }

  private getContentOffsetAndSequence(fileName: string): string[] {
    const parts = fileName.split("_");
    if (parts.length != 4) {
      throw new Error(`Invalid file name format: ${fileName}`);
    }
    return fileName.split("_").slice(-2);
  }
}