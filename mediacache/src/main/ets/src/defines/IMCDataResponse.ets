import { MCRange } from "../utils/MCRange";
import { IMCMediaContentLoader } from "./IMCMediaContentLoader";

export interface IMCDataResponse {
  readonly statusCode: number;
}

export interface IMCDataOkResponse extends IMCDataResponse {
  readonly statusCode: 200;
  readonly contentType: string;    // mime type;
  readonly contentLength?: number;  // file data total length;
  readonly byteRangeAccessSupported: boolean;
  readonly contentLoaders: IMCMediaContentLoader[];
}

export interface IMCDataPartialContentResponse extends IMCDataResponse {
  readonly statusCode: 206;
  readonly contentType: string;    // mime type;
  readonly contentRange: MCRange
  readonly totalLength: number;    // file data total length;
  readonly contentLoaders: IMCMediaContentLoader[];
}