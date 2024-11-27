import { IMCHttpRequest } from "./IMCHttpRequest";

export type MCDataDecryptHandler = (request: IMCHttpRequest, offset: number, data: ArrayBuffer, len: number) => number | Promise<number>;