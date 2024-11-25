import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCMediaContent } from "./MCMediaContent";
import { fileIo, statfs } from "@kit.CoreFileKit";

export class MCMediaContentProvider {
  private mDir: string;
  private mPrefix: string; // file name prefix of content
  private mLastIndexes = new Map<number, number>(); // key: contentOffset, value: index;

  constructor(dir: string, prefix: string) {
    this.mDir = dir;
    this.mPrefix = prefix;
  }

  /** 加载目录下缓存的媒体内容; */
  async prepare(): Promise<IMCMediaContent[] | undefined> {
    const fileNames = await fileIo.listFile(this.mDir);
    return Promise.all(fileNames.filter((fileName) => fileName.startsWith(this.mPrefix)).map(async (fileName) => {
      const filePath = `${this.mDir}/${fileName}`;
      const fileSize = await statfs.getTotalSize(filePath);
      const props = this.getContentOffsetAndIndex(fileName);
      const contentOffset = parseInt(props[0], 10);
      const index = parseInt(props[1], 10);
      const lastIndex = this.mLastIndexes.get(contentOffset);
      if ( lastIndex === undefined || lastIndex < index ) this.mLastIndexes.set(contentOffset, index);
      return new MCMediaContent(contentOffset, filePath, fileSize);
    }));
  }

  createContent(contentOffset: number): IMCMediaContent {
    const lastIndex = this.mLastIndexes.get(contentOffset);
    const index = lastIndex === undefined ? 0 : lastIndex + 1;
    const fileName = this.generateFileName(contentOffset, index);
    const filePath = `${this.mDir}/${fileName}`;
    const content = new MCMediaContent(contentOffset, filePath);
    this.mLastIndexes.set(contentOffset, index);
    return content;
  }

  private generateFileName(contentOffset: number, index: number): string {
    return `${this.mPrefix}_${contentOffset}_${index}`;
  }

  private getContentOffsetAndIndex(fileName: string): string[] {
    const parts = fileName.split("_");
    if (parts.length != 3) {
      throw new Error(`Invalid file name format: ${fileName}`);
    }
    return fileName.split("_").slice(-2);
  }
}