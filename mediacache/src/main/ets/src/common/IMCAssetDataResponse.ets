export enum MCAssetDataResponseType {
  BAD_REQUEST,
  INTERNAL_ERROR,
  OK,
  PARTIAL_CONTENT,
}

export interface IMCAssetDataResponse {
  success: boolean;
  type: MCAssetDataResponseType;
}

export interface IMCAssetDataBadRequestResponse extends IMCAssetDataResponse {
  success: false;
  type: MCAssetDataResponseType.BAD_REQUEST;
}

export interface IMCAssetDataInternalErrorResponse extends IMCAssetDataResponse {
  success: false;
  type: MCAssetDataResponseType.INTERNAL_ERROR;
}

export interface IMCAssetDataOkResponse extends IMCAssetDataResponse {
  success: true;
  contentType: string;    // mime type;
  contentLength: number;  // file data total length;
  byteRangeAccessSupported: boolean;
  type: MCAssetDataResponseType.OK;
}

export interface IMCAssetDataPartialContentResponse extends IMCAssetDataResponse {
  success: true;
  contentType: string;    // mime type;
  contentOffset: number;
  contentLength: number;
  totalLength: number;    // file data total length;
  type: MCAssetDataResponseType.PARTIAL_CONTENT;
}