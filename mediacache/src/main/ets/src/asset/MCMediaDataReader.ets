import { IMCMediaDataReader } from "../common/IMCMediaDataReader";
import { IMCMediaDataResponse } from "../common/IMCMediaDataResponse";

export class MCMediaDataReader implements IMCMediaDataReader {
  get readableLength(): Promise<number> {
    throw new Error("Method not implemented.");
  }
  get response(): Promise<IMCMediaDataResponse | undefined> {
    throw new Error("Method not implemented.");
  }
  get isDone(): Promise<boolean> {
    throw new Error("Method not implemented.");
  }
  get isAborted(): Promise<boolean> {
    throw new Error("Method not implemented.");
  }

  prepare(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  readData(capacity: number): Promise<ArrayBuffer | undefined> {
    throw new Error("Method not implemented.");
  }

  seekToEndOfReadableRange(): Promise<number> {
    throw new Error("Method not implemented.");
  }

  abort(error?: Error | undefined): Promise<void> {
    throw new Error("Method not implemented.");
  }

  // on(event: 'responseReady', callback: (reader: IMCMediaDataReader, response: IMCMediaDataResponse) => void): Promise<void>;
  // off(event: 'responseReady'): Promise<void>;

  // on(event: "newDataReadable", callback: (reader: IMCMediaDataReader) => void): Promise<void>;
  // off(event: "newDataReadable"): Promise<void>;
  //
  // on(event: "aborted", callback: (reader: IMCMediaDataReader, error?: Error | undefined) => void): Promise<void>;
  // off(event: "aborted"): Promise<void>;

  on(event: string, callback: Object): Promise<void> {
    throw new Error("Method not implemented.");
  }

  off(event: string): Promise<void> {
    throw new Error("Method not implemented.");
  }
}