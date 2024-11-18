// client connection message -> request -> ??? -> response

export interface IMCHttpResponse {
  readonly contentLength: number;
  readonly isDone: boolean;

  readData(length: number): Promise<void>;
  on(event: 'newDataAvailable', callback: (response: IMCHttpResponse) => void): void;
}

