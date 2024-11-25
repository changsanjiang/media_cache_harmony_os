// https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Messages
// https://datatracker.ietf.org/doc/html/rfc9110#name-host-and-authority
//
// GET /pub/WWW/ HTTP/1.1
// Host: www.example.org
//
export interface IMCHttpRequest {
  method: string; // 请求方法 (如 GET, HEAD)
  requestTarget: string; // 请求目标 (如 "/index.html")
  // host: string; // Host 头字段
  headers: Record<string, string>; // 所有的请求头字段; key 都被转成了小写字母;
}