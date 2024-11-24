export interface IMCMediaContentLoader {
  readonly isDone: Promise<boolean>;
  readonly isAborted: Promise<boolean>;

  prepare(): Promise<void>;
  readData(buffer: ArrayBuffer): Promise<number>;
  abort(error?: Error): Promise<void>;

  // Event when new data is available for reading.
  on(event: 'dataLoaded', callback: (loader: IMCMediaContentLoader, length: number) => void): Promise<void>;
  off(event: 'dataLoaded'): Promise<void>;

  on(event: 'aborted', callback: (loader: IMCMediaContentLoader, error?: Error) => void): Promise<void>;
  off(event: 'aborted'): Promise<void>;
}