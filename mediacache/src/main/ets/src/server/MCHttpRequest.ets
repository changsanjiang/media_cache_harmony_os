// https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Messages
export interface IMCHttpRequest {
  method: string;
  requestTarget: string;
  host: string;
  headers: Record<string, string>; // 所有的请求头字段
}

// GET or HEAD request;
export function parseHttpRequest(rawMessage: string): IMCHttpRequest {
  // 分离 header 部分和 body;
  const delimiterIndex = rawMessage.indexOf("\r\n\r\n");
  let headerPart: string;
  let bodyPart: string;

  if (delimiterIndex !== -1) {
    headerPart = rawMessage.slice(0, delimiterIndex);
    bodyPart = rawMessage.slice(delimiterIndex + 4);
  } else {
    headerPart = rawMessage;
    bodyPart = "";
  }

  // 不解析 body; 如果存在消息体部分, 抛出异常;
  if (bodyPart && bodyPart.trim().length > 0) {
    throw new Error("Request contains a body, which is not supported.");
  }

  const headerLines = headerPart.split("\r\n");

  // 解析起始行
  const startLine = headerLines.shift();
  if (!startLine) {
    throw new Error("Invalid HTTP message: Missing start line.");
  }

  // 分割起始行，获取 method, requestTarget, 和 httpVersion
  let startLineParts = startLine.split(" ");
  if (startLineParts.length !== 3) {
    throw new Error("Invalid start line format.");
  }
  const method = startLineParts[0];
  const requestTarget = startLineParts[1];
  const httpVersion = startLineParts[2];
  if (httpVersion !== "HTTP/1.1") {
    throw new Error("Unsupported HTTP version. Only HTTP/1.1 is supported.");
  }

  // 解析头部字段
  const headers: Record<string, string> = {};
  for (let i = 0; i < headerLines.length; i++) {
    const line = headerLines[i];
    const separatorIndex = line.indexOf(": ");
    if (separatorIndex === -1) {
      throw new Error(`Invalid header line: ${line}`);
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 2).trim();
    headers[key] = value;
  }

  // 验证 Host 头
  const host = headers["Host"];
  if (!host) {
    throw new Error("Invalid HTTP/1.1 message: Missing 'Host' header.");
  }

  return {
    method: method,
    requestTarget: requestTarget,
    host: host,
    headers: headers
  }
}