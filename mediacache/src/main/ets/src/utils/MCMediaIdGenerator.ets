import MCUtils from "./MCUtils";

export namespace MCMediaIdGenerator {
  /**
   * 为每个媒体生成一个唯一标识符;
   * */
  export function generate(uri: string): Promise<string> {
    return MCUtils.hash(uri);
  }
}