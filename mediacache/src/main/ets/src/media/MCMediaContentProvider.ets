import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCMediaContent } from "./MCMediaContent";
import { fileIo, statfs } from "@kit.CoreFileKit";

export class MCMediaContentProvider {
  private mMediaId: string;
  private mDir: string;
  private mPrefix: string; // file name prefix of content
  private mSequence = 0; // file sequence number of content

  constructor(mediaId: string, dir: string, prefix: string) {
    this.mMediaId = mediaId;
    this.mDir = dir;
    this.mPrefix = prefix;
  }

  /** 加载目录下缓存的媒体内容; */
  async prepare(): Promise<IMCMediaContent[] | undefined> {
    const exists = await fileIo.access(this.mDir, fileIo.AccessModeType.EXIST);
    if ( !exists ) {
      await fileIo.mkdir(this.mDir);
      await fileIo.mkdir(`${this.mDir}/temp`)
    }

    return undefined;

    // const fileNames = await fileIo.listFile(this.mDir);
    // const contentFileNames = fileNames.length > 0 ? fileNames.filter((fileName) => fileName.startsWith(this.mPrefix)) : undefined;
    // return contentFileNames && contentFileNames.length > 0 ? Promise.all(contentFileNames.map(async (fileName) => {
    //   const filePath = `${this.mDir}/${fileName}`;
    //   const fileSize = await statfs.getTotalSize(filePath);
    //   const props = this.getContentOffsetAndSequence(fileName);
    //   const contentOffset = parseInt(props[0], 10);
    //   const sequence = parseInt(props[1], 10);
    //   if ( this.mSequence < sequence ) this.mSequence = sequence;
    //   return new MCMediaContent(this.mMediaId, contentOffset, filePath, fileSize);
    // })) : undefined;
  }

  createContent(contentOffset: number, temp: boolean = false): IMCMediaContent {
    const sequence = this.mSequence + 1;
    this.mSequence = sequence;
    const fileName = this.generateFileName(contentOffset, sequence);
    const filePath = !temp ? `${this.mDir}/${fileName}` : `${this.mDir}/temp/${fileName}`;
    const content = new MCMediaContent(this.mMediaId, contentOffset, filePath, 0, temp);
    return content;
  }

  async removeAllTempContentFiles(): Promise<void> {
    try {
      const dir = `${this.mDir}/temp`;
      await fileIo.unlink(dir);
      await fileIo.mkdir(`${this.mDir}/temp`)
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