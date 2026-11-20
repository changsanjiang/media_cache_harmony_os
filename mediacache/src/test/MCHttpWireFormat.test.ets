import { describe, it, expect } from '@ohos/hypium';
import { MCHttpWireFormat } from '../main/ets/src/server/MCHttpWireFormat';

export default function mcHttpWireFormatTest() {
  describe('MCHttpWireFormat', () => {
    it('formatErrorResponse 400', 0, () => {
      const raw = MCHttpWireFormat.formatErrorResponse(400);
      expect(raw).assertContain('HTTP/1.1 400 Bad Request');
      expect(raw).assertContain('\r\n\r\n');
    });

    it('formatResponseHeaders 200', 0, () => {
      const raw = MCHttpWireFormat.formatResponseHeaders({
        statusCode: 200,
        contentType: 'video/mp4',
        contentLength: 1024,
        byteRangeAccessSupported: true,
        chunked: false,
      });
      expect(raw).assertContain('HTTP/1.1 200 OK');
      expect(raw).assertContain('Content-Length: 1024');
      expect(raw).assertContain('Accept-Ranges: bytes');
    });

    it('wrapChunkedBody prefix', 0, () => {
      const body = new ArrayBuffer(3);
      const chunked = new Uint8Array(MCHttpWireFormat.wrapChunkedBody(body));
      expect(chunked[0]).assertEqual(0x33);
      expect(chunked[1]).assertEqual(0x0d);
      expect(chunked[2]).assertEqual(0x0a);
    });
  });
}