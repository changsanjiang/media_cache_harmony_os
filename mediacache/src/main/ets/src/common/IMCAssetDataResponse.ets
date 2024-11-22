export enum MCAssetDataResponseType {
  BAD_REQUEST,
  INTERNAL_ERROR,
  OK,
  PARTIAL_CONTENT,
}

export interface IMCAssetDataResponse {
  type: MCAssetDataResponseType;
}

export interface IMCAssetDataBadRequestResponse extends IMCAssetDataResponse {
  type: MCAssetDataResponseType.BAD_REQUEST;
}

export interface IMCAssetDataInternalErrorResponse extends IMCAssetDataResponse {
  type: MCAssetDataResponseType.INTERNAL_ERROR;
}

export interface IMCAssetDataOkResponse extends IMCAssetDataResponse {
  contentType: string;    // mime type;
  contentLength: number;  // file data total length;
  byteRangeAccessSupported: boolean;
  type: MCAssetDataResponseType.OK;
}

export interface IMCAssetDataPartialContentResponse extends IMCAssetDataResponse {
  contentType: string;    // mime type;
  contentOffset: number;
  contentLength: number;
  totalLength: number;    // file data total length;
  type: MCAssetDataResponseType.PARTIAL_CONTENT;
}