import {
  IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders
} from '../defines/IMCHttpResponseHeaders';
import { MCLogModule } from '../defines/MCLogModule';
import MCLogger from '../utils/MCLogger';
import { buffer, util } from '@kit.ArkTS';

/** HTTP/1.1 出站线格式：状态行、头字段、chunked 包装。 */
export namespace MCHttpWireFormat {
  export function formatErrorResponse(statusCode: 400 | 500): string {
    const currentDate = new Date().toUTCString();
    if (statusCode === 400) {
      return `HTTP/1.1 400 Bad Request\r\nDate: ${currentDate}\r\n\r\n`;
    }
    return `HTTP/1.1 500 Internal Server Error\r\nDate: ${currentDate}\r\n\r\n`;
  }

  export function formatResponseHeaders(responseHeaders: IMCHttpResponseHeaders, clientId?: number): string {
    const currentDate = new Date().toUTCString();
    switch (responseHeaders.statusCode) {
      case 200: {
        const okResponse = responseHeaders as IMCHttpOkResponseHeaders;
        return (
          `HTTP/1.1 200 OK\r\n` +
            `Content-Type: ${okResponse.contentType}\r\n` +
            (okResponse.chunked === true ? `Transfer-Encoding: chunked\r\n` : '') +
            (okResponse.contentLength !== undefined ? `Content-Length: ${okResponse.contentLength}\r\n` : '') +
            (okResponse.byteRangeAccessSupported === true ? `Accept-Ranges: bytes\r\n` : '') +
            `Access-Control-Allow-Origin: *\r\n` +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        );
      }
      case 206: {
        const partialResponse = responseHeaders as IMCHttpPartialContentResponseHeaders;
        return (
          `HTTP/1.1 206 Partial Content\r\n` +
            `Content-Range: bytes ${partialResponse.contentRange.location}-${partialResponse.contentRange.max - 1}/${partialResponse.totalLength}\r\n` +
            `Content-Type: ${partialResponse.contentType}\r\n` +
            `Content-Length: ${partialResponse.contentRange.length}\r\n` +
            `Accept-Ranges: bytes\r\n` +
            `Access-Control-Allow-Origin: *\r\n` +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        );
      }
      case 400:
        return formatErrorResponse(400);
      default: {
        if (responseHeaders.statusCode !== 500) {
          MCLogger.warn(MCLogModule.MCHttpWireFormat, () =>
            MCLogger.withClient(clientId ?? -1, `unsupported status ${responseHeaders.statusCode}`));
        }
        return formatErrorResponse(500);
      }
    }
  }

  export function encodeChunkedBodySegment(data: ArrayBuffer): ArrayBuffer {
    const uint8Array = new Uint8Array(data);
    const chunkSizeHex = uint8Array.byteLength.toString(16);
    const encoder = new util.TextEncoder('utf-8');
    const chunkHeader = encoder.encodeInto(chunkSizeHex + '\r\n');
    const chunkFooter = encoder.encodeInto('\r\n');
    const totalSize = chunkHeader.byteLength + uint8Array.byteLength + chunkFooter.byteLength;

    const chunkedData = new ArrayBuffer(totalSize);
    const dataView = new Uint8Array(chunkedData);
    dataView.set(chunkHeader, 0);
    dataView.set(uint8Array, chunkHeader.byteLength);
    dataView.set(chunkFooter, chunkHeader.byteLength + uint8Array.byteLength);
    return chunkedData;
  }

  export function formatChunkedTerminator(): ArrayBuffer {
    return buffer.from('0\r\n\r\n', 'utf-8').buffer;
  }
}