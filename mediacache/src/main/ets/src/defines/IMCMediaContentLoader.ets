/** 数据加载器; */
export interface IMCMediaContentLoader {
  prepare(): Promise<void>;
  abort(error?: Error): Promise<void>; // 取消加载;

  on(event: 'dataLoad', callback: (loader: IMCMediaContentLoader, offset: number, data: ArrayBuffer) => void | Promise<void>): void;
  off(event: 'dataLoad'): void;

  on(event: 'dataEnd', callback: (loader: IMCMediaContentLoader) => void): void;
  off(event: 'dataEnd'): void;

  on(event: 'aborted', callback: (loader: IMCMediaContentLoader, error?: Error) => void): void;
  off(event: 'aborted'): void;
}