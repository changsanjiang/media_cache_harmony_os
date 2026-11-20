import { MCLogModule } from '../defines/MCLogModule';
import MCLogger from '../utils/MCLogger';

/** 单条连接上累积 TCP 字节，按 HTTP 头块切分。 */
export class MCHttpReceiveBuffer {
  private mChunks: Uint8Array[] = [];
  private mLength = 0;
  private mClientId: number;
  private mMaxBytes: number;

  constructor(
    clientId: number,
    maxBytes: number = 64 * 1024
  ) {
    this.mClientId = clientId;
    this.mMaxBytes = maxBytes;
  }

  append(data: ArrayBuffer): void {
    const chunk = new Uint8Array(data);
    if ( chunk.byteLength === 0 ) {
      return;
    }
    if ( this.mLength + chunk.byteLength > this.mMaxBytes ) {
      throw new Error(`HTTP receive buffer exceeded ${this.mMaxBytes} bytes`);
    }
    this.mChunks.push(chunk);
    this.mLength += chunk.byteLength;
  }

  /** 若已有完整请求头（以 {@code \\r\\n\\r\\n} 结束），取出并返回；否则 undefined。 */
  takeCompleteRequestHeaders(): string | undefined {
    const merged = this.peekMerged();
    const delimiter = this.indexOfCrlfCrlf(merged);
    if ( delimiter < 0 ) {
      return undefined;
    }

    const headerBytes = merged.subarray(0, delimiter);
    const consumed = delimiter + 4;
    this.dropLeadingBytes(consumed);

    const headerText = this.decodeAscii(headerBytes);
    MCLogger.trace(MCLogModule.MCHttpReceiveBuffer, () =>
      MCLogger.withClient(this.mClientId, `header block ${headerBytes.byteLength}B, pending ${this.mLength}B`));
    return headerText;
  }

  private peekMerged(): Uint8Array {
    const merged = new Uint8Array(this.mLength);
    let offset = 0;
    for (const chunk of this.mChunks) {
      merged.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return merged;
  }

  private dropLeadingBytes(consumed: number): void {
    if ( consumed <= 0 ) {
      return;
    }
    let skip = consumed;
    while (skip > 0 && this.mChunks.length > 0) {
      const head = this.mChunks[0];
      if ( head.byteLength <= skip ) {
        skip -= head.byteLength;
        this.mLength -= head.byteLength;
        this.mChunks.shift();
      }
      else {
        this.mChunks[0] = head.subarray(skip);
        this.mLength -= skip;
        skip = 0;
      }
    }
  }

  private indexOfCrlfCrlf(buf: Uint8Array): number {
    for (let i = 0; i + 3 < buf.byteLength; i++) {
      if (buf[i] === 0x0d && buf[i + 1] === 0x0a && buf[i + 2] === 0x0d && buf[i + 3] === 0x0a) {
        return i;
      }
    }
    return -1;
  }

  private decodeAscii(buf: Uint8Array): string {
    let raw = '';
    for (let i = 0; i < buf.byteLength; i++) {
      raw += String.fromCharCode(buf[i]);
    }
    return raw;
  }
}