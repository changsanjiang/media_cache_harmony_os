import { IMCDataFetcher } from "../media/IMCDataFetcher";

export class MCAssetDataFetcher implements IMCDataFetcher {
  prepare(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  abort(error?: Error | undefined): Promise<void> {
    throw new Error("Method not implemented.");
  }

  on(event: "responseReceive",
    callback: (reader: IMCDataFetcher, responseHeaders: string) => void | Promise<void>): void;

  on(event: "dataReceive", callback: (reader: IMCDataFetcher, data: ArrayBuffer) => void | Promise<void>): void;

  on(event: "dataEnd", callback: (reader: IMCDataFetcher) => void): void;

  on(event: "aborted", callback: (reader: IMCDataFetcher, error?: Error | undefined) => void): void;

  on(event: "responseReceive",
    callback: (reader: IMCDataFetcher, responseHeaders: string) => void | Promise<void>): void {
    throw new Error("Method not implemented.");
  }

  off(event: "responseReceive"): void;

  off(event: "dataReceive"): void;

  off(event: "dataEnd"): void;

  off(event: "aborted"): void;

  off(event: "responseReceive"): void {
    throw new Error("Method not implemented.");
  }

}