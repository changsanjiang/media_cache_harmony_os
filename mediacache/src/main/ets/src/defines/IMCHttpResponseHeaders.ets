import { MCRange } from "../utils/MCRange";

export interface IMCHttpResponseHeaders {
  readonly statusCode: number;
}

export interface IMCHttpOkResponseHeaders extends IMCHttpResponseHeaders {
  readonly statusCode: 200;
  readonly contentType: string;    // mime type;
  readonly chunked?: boolean; // Transfer-Encoding;
  readonly contentLength?: number;  // file data total length;
  readonly byteRangeAccessSupported?: boolean;
}

export interface IMCHttpPartialContentResponseHeaders extends IMCHttpResponseHeaders {
  readonly statusCode: 206;
  readonly contentType: string;    // mime type;
  readonly contentRange: MCRange;
  readonly totalLength: number;    // file data total length;
}