export enum MCMediaDataResponseType {
  BAD_REQUEST,
  INTERNAL_ERROR,
  OK,
  PARTIAL_CONTENT,
}

export interface IMCMediaDataResponse {
  type: MCMediaDataResponseType;
}

export interface IMCMediaDataBadRequestResponse extends IMCMediaDataResponse {
  type: MCMediaDataResponseType.BAD_REQUEST;
}

export interface IMCMediaDataInternalErrorResponse extends IMCMediaDataResponse {
  type: MCMediaDataResponseType.INTERNAL_ERROR;
}

export interface IMCMediaDataOkResponse extends IMCMediaDataResponse {
  contentType: string;    // mime type;
  contentLength: number;  // file data total length;
  byteRangeAccessSupported: boolean;
  type: MCMediaDataResponseType.OK;
}

export interface IMCMediaDataPartialContentResponse extends IMCMediaDataResponse {
  contentType: string;    // mime type;
  contentOffset: number;
  contentLength: number;
  totalLength: number;    // file data total length;
  type: MCMediaDataResponseType.PARTIAL_CONTENT;
}