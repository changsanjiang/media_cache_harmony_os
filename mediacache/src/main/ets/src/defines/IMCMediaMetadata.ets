export interface IMCMediaMetadata {
  readonly contentType: string;
  readonly totalLength: number; // 长度未知时返回 Number.MAX_SAFE_INTEGER;
  readonly byteRangeAccessSupported: boolean;
}