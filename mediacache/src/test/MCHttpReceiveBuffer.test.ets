import { describe, it, expect } from '@ohos/hypium';
import { MCHttpReceiveBuffer } from '../main/ets/src/server/MCHttpReceiveBuffer';

function encodeAscii(text: string): ArrayBuffer {
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    bytes[i] = text.charCodeAt(i);
  }
  return bytes.buffer;
}

export default function mcHttpReceiveBufferTest() {
  describe('MCHttpReceiveBuffer', () => {
    it('waits until CRLFCRLF present', 0, () => {
      const buffer = new MCHttpReceiveBuffer(1);
      buffer.append(encodeAscii('GET /x HTTP/1.1\r\nHost: h\r'));
      expect(buffer.tryShiftCompleteHeaderBlock()).assertUndefined();
      buffer.append(encodeAscii('\n\r\n'));
      const block = buffer.tryShiftCompleteHeaderBlock();
      expect(block).assertContain('GET /x HTTP/1.1');
    });

    it('shifts two requests from one append', 0, () => {
      const buffer = new MCHttpReceiveBuffer(2);
      const req1 = 'GET /a HTTP/1.1\r\nHost: h\r\n\r\n';
      const req2 = 'HEAD /b HTTP/1.1\r\nHost: h\r\n\r\n';
      buffer.append(encodeAscii(req1 + req2));

      const first = buffer.tryShiftCompleteHeaderBlock();
      expect(first).assertContain('GET /a');
      const second = buffer.tryShiftCompleteHeaderBlock();
      expect(second).assertContain('HEAD /b');
      expect(buffer.tryShiftCompleteHeaderBlock()).assertUndefined();
    });
  });
}