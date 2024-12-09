import { IMCDataRequest } from "./IMCDataRequest";

export type MCDataDecryptHandler = (request: IMCDataRequest, offset: number, data: ArrayBuffer) => number | Promise<number>;