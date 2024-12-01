import { IMCHttpRequestRange } from "./IMCHttpRequestRange";

export interface IMCDataRequest { // GET Request;
  readonly requestTarget: string; // 请求目标 (如 "/index.html")
  readonly headers: Record<string, string>; // 所有的请求头字段; key 都被转成了小写字母;

  // 优先通过 range 属性获取请求范围;
  // 如果 range 未设置, 将会尝试从 headers 中获取请求范围;
  readonly range?: IMCHttpRequestRange;
}