export interface IMCMediaContentLoader {
  readonly isDone: Promise<boolean>;
  readonly isAborted: Promise<boolean>;

  prepare(): Promise<void>;
  readData(capacity: number): Promise<ArrayBuffer | undefined>;
  abort(error?: Error): Promise<void>;

  // Event when new data is available for reading.
  on(event: 'dataLoaded', callback: (loader: IMCMediaContentLoader, data: ArrayBuffer) => void): Promise<void>;
  off(event: 'dataLoaded'): Promise<void>;

  on(event: 'aborted', callback: (loader: IMCMediaContentLoader, error?: Error) => void): Promise<void>;
  off(event: 'aborted'): Promise<void>;
}