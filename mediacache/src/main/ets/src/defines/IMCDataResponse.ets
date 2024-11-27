export enum MCDataResponseStatusCode {
  BAD_REQUEST,
  INTERNAL_ERROR,
  OK,
  PARTIAL_CONTENT,
}

export interface IMCDataResponse {
  statusCode: MCDataResponseStatusCode;
}

export interface IMCDataBadRequestResponse extends IMCDataResponse {
  statusCode: MCDataResponseStatusCode.BAD_REQUEST;
}

export interface IMCDataInternalErrorResponse extends IMCDataResponse {
  statusCode: MCDataResponseStatusCode.INTERNAL_ERROR;
}

export interface IMCDataOkResponse extends IMCDataResponse {
  contentType: string;    // mime type;
  contentLength: number;  // file data total length;
  byteRangeAccessSupported: boolean;
  statusCode: MCDataResponseStatusCode.OK;
}

export interface IMCDataPartialContentResponse extends IMCDataResponse {
  contentType: string;    // mime type;
  contentOffset: number;
  contentLength: number;
  totalLength: number;    // file data total length;
  statusCode: MCDataResponseStatusCode.PARTIAL_CONTENT;
}