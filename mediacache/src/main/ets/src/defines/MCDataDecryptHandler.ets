import { IMCDataRequest } from "./IMCDataRequest";

export type MCDataDecryptHandler = (request: IMCDataRequest, offset: number, data: ArrayBuffer, len: number) => number | Promise<number>;