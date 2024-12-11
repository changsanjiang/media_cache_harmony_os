export interface IMCDataRequest { // GET Request;
  readonly requestTarget: string; // 请求目标 (如 "/index.html")
  readonly headers?: Record<string, string>; // 所有的请求头字段; key 都被转成了小写字母;
}