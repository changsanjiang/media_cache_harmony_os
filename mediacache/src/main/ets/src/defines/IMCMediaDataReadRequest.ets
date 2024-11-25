import { IMCHttpRequest } from "./IMCHttpRequest";

export interface IMCMediaDataReadRequest {
  readonly mediaId: string;
  readonly proxyRequest: IMCHttpRequest;
}