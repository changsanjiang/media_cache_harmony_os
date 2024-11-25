import { IMCMediaDataReader } from "../defines/IMCMediaDataReader";
import { IMCMediaDataResponse } from "../defines/IMCMediaDataResponse";
import MCLogger from "../utils/MCLogger";

export class MCMediaDataReader implements IMCMediaDataReader {
  private mClientId: number;

  constructor(clientId: number) {
    this.mClientId = clientId;
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCMediaDataReader][clientId: ${this.mClientId}] New DataReader instance created.`);
  }

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