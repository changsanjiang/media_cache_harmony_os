export type MCHttpMethod = 'GET' | 'HEAD';

export interface IMCDataRequest {
  readonly requestTarget: string; // 一般为代理路径(proxyPath)
  readonly headers?: Record<string, string>; // key 为小写
  /** 默认 GET */
  readonly method?: MCHttpMethod;
}