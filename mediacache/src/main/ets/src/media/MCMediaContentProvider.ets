import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCMediaContent } from "./MCMediaContent";
import { fileIo } from "@kit.CoreFileKit";
import { IMCMediaMetadata } from "../defines/IMCMediaMetadata";
import { MCUtils } from "../../../../../Index";
import { JSON } from "@kit.ArkTS";

export class MCMediaContentProvider {
  private mMediaId: string;
  private mDir: string;
  private mPrefix: string; // content file name prefix of content
  private mSequence = 0; // content file sequence number of content

  constructor(mediaId: string, dir: string, prefix: string) {
    this.mMediaId = mediaId;
    this.mDir = dir;
    this.mPrefix = prefix;
  }

  async prepare(): Promise<void> {
    const exists = await fileIo.access(this.mDir, fileIo.AccessModeType.EXIST);
    if ( !exists ) {
      await fileIo.mkdir(this.mDir);
      await fileIo.mkdir(`${this.mDir}/mc_temp`)
    }
  }

  async loadMetadata(): Promise<IMCMediaMetadata | undefined> {
    try {
      const fileName = 'mc_media_metadata.json';
      const filePath = `${this.mDir}/${fileName}`;
      const exists = await fileIo.access(filePath, fileIo.AccessModeType.EXIST);
      if ( exists ) {
        const content = await fileIo.readText(filePath, { encoding: 'utf-8' });
        const record = JSON.parse(content) as Record<string, string>;
        const checksum = record['checksum'];
        const jsonStr = record['data'];
        const calculatedChecksum = await MCUtils.hash(jsonStr);
        if ( checksum === calculatedChecksum ) {
          return JSON.parse(jsonStr) as IMCMediaMetadata;
        }
      }
    }
    catch (error) { }
    return undefined;
  }

  async saveMetadata(metadata: IMCMediaMetadata): Promise<boolean> {
    try {
      const jsonStr = JSON.stringify(metadata);
      const checksum = await MCUtils.hash(jsonStr);
      const record: Record<string, string> = {
        'checksum': checksum,
        'data': jsonStr
      };
      const content = JSON.stringify(record);
      const buffer = MCUtils.stringToBuffer(content);
      const fileName = 'mc_media_metadata.json';
      const filePath = `${this.mDir}/${fileName}`;
      const file = await fileIo.open(filePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC | fileIo.OpenMode.CREATE);
      await fileIo.write(file.fd, buffer);
      return true;
    }
    catch (error) { }
    return false;
  }

  /** 加载目录下缓存的媒体内容; */
  async loadContents(): Promise<IMCMediaContent[] | undefined> {
    const fileNames = await fileIo.listFile(this.mDir);
    const contentFileNames = fileNames.length > 0 ? fileNames.filter((fileName) => fileName.startsWith(this.mPrefix)) : undefined;
    return contentFileNames && contentFileNames.length > 0 ? Promise.all(contentFileNames.map(async (fileName) => {
      const filePath = `${this.mDir}/${fileName}`;
      const fileSize = (await fileIo.stat(filePath)).size;
      const props = this.getContentOffsetAndSequence(fileName);
      const contentOffset = parseInt(props[0], 10);
      const sequence = parseInt(props[1], 10);
      if ( this.mSequence < sequence ) this.mSequence = sequence;
      return new MCMediaContent(this.mMediaId, contentOffset, filePath, fileSize);
    })) : undefined;
  }

  createContent(contentOffset: number, temp: boolean = false): IMCMediaContent {
    const sequence = this.mSequence + 1;
    this.mSequence = sequence;
    const fileName = this.generateFileName(contentOffset, sequence);
    const filePath = !temp ? `${this.mDir}/${fileName}` : `${this.mDir}/mc_temp/${fileName}`;
    const content = new MCMediaContent(this.mMediaId, contentOffset, filePath, 0, temp);
    return content;
  }

  async removeAllTempContentFiles(): Promise<void> {
    try {
      const dir = `${this.mDir}/mc_temp`;
      await fileIo.unlink(dir);
      await fileIo.mkdir(`${this.mDir}/mc_temp`)
    }
    catch (error) {
    }
  }

  /** file name format: `prefix_contentOffset_sequence`; */
  private generateFileName(contentOffset: number, sequence: number): string {
    return `${this.mPrefix}_${contentOffset}_${sequence}`;
  }

  private getContentOffsetAndSequence(fileName: string): string[] {
    const parts = fileName.split("_");
    if (parts.length != 3) {
      throw new Error(`Invalid file name format: ${fileName}`);
    }
    return fileName.split("_").slice(-2);
  }
}