export interface IMCMediaMetadata {
  readonly contentType: string;
  readonly totalLength: number; // 服务器未返回时为 -1;
  readonly byteRangeAccessSupported: boolean;
}