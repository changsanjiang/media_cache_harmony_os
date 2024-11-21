export interface IMCDataReader {
  readonly readableLength: Promise<number>;
  readonly response: Promise<string | undefined>;
  readonly isDone: Promise<boolean>;
  readonly isAborted: Promise<boolean>;

  prepare(): Promise<void>
  readData(capacity: number): Promise<ArrayBuffer | undefined>;
  seekTo(offset: number): Promise<void>;
  abort(error?: Error): Promise<void>;

  on(event: 'newDataReadable', callback: (reader: IMCDataReader) => void): Promise<void>;
  off(event: 'newDataReadable'): Promise<void>;

  on(event: 'aborted', callback: (reader: IMCDataReader, error?: Error) => void): Promise<void>; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): Promise<void>;
}

// https://datatracker.ietf.org/doc/html/rfc9110#name-example-message-exchange
//
// HTTP/1.1 200 OK
// Date: Mon, 27 Jul 2009 12:28:53 GMT
// Server: Apache
// Last-Modified: Wed, 22 Jul 2009 19:15:56 GMT
// ETag: "34aa387-d-1568eb00"
// Accept-Ranges: bytes
// Content-Length: 51
// Vary: Accept-Encoding
// Content-Type: text/plain
//
// Hello World! My content includes a trailing CRLF.

// https://datatracker.ietf.org/doc/html/rfc9110#name-single-part
//
// HTTP/1.1 206 Partial Content
// Date: Wed, 15 Nov 1995 06:25:24 GMT
// Last-Modified: Wed, 15 Nov 1995 04:58:08 GMT
// Content-Range: bytes 21010-47021/47022
// Content-Length: 26012
// Content-Type: image/gif
//
// ... 26012 bytes of partial image data ...

// let mime = await this.source.getMime();
// let mimeKnown = mime != null && mime != undefined && mime.length > 0;
// let length = this.cache.isCompleted() ? this.cache.available() : await this.source.length();
// let lengthKnown = length >= 0;
// let contentLength = request.partial ? length - request.rangeOffset : length;
// let addRange = lengthKnown && request.partial;
// let lengthStr = lengthKnown ? `Content-Length: ${contentLength}${"\n"} ` : ""
// let rangeStr = addRange ? `Content-Range: bytes ${request.rangeOffset}-${length - 1}/${length}${"\n"}` : ""
// let mimeStr = mimeKnown ? `Content-Type: ${mime}${"\n"}` : ""
//
// let str1 = `HTTP/1.1 206 PARTIAL CONTENT${"\n"}${"Accept-Ranges: bytes\n"}${lengthStr}${rangeStr}${mimeStr}${"\n"}`;
// let str2 = `HTTP/1.1 200 OK${"\n"}${"Accept-Ranges: bytes\n"}${lengthStr}${rangeStr}${mimeStr}${"\n"}`;
//
// return Promise.resolve(`${request.partial ? str1 : str2}`);