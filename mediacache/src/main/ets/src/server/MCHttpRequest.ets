import MCLogger from "../utils/MCLogger";

// https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Messages
export interface IMCHttpRequest {
  method: string; // 请求方法 (如 GET, HEAD)
  requestTarget: string; // 请求目标 (如 "/index.html")
  host: string; // Host 头字段
  headers: Record<string, string>; // 所有的请求头字段
}

/**
 * 解析原始 HTTP 请求消息，仅处理 GET 和 HEAD 请求。
 *
 * @param rawMessage - 原始 HTTP 请求字符串
 * @returns IMCHttpRequest - 解析后的 HTTP 请求对象
 * @throws Error - 如果消息格式无效、不支持的 HTTP 方法或存在消息体，则抛出异常
 */
export function parseHttpRequest(rawMessage: string): IMCHttpRequest {
  MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCHttpRequest] Start parsing HTTP request with rawMessage: ${rawMessage}`);

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
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest] Request contains a body, which is not supported.`);
    throw new Error("Request contains a body, which is not supported.");
  }

  const headerLines = headerPart.split("\r\n");

  // 解析起始行
  const startLine = headerLines.shift();
  if (!startLine) {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest] Invalid HTTP message: Missing start line.`);
    throw new Error("Invalid HTTP message: Missing start line.");
  }

  // 分割起始行，获取 method, requestTarget, 和 httpVersion
  let startLineParts = startLine.split(" ");
  if (startLineParts.length !== 3) {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest] Invalid start line format: ${startLine}`);
    throw new Error(`Invalid start line format: ${startLine}`);
  }
  const method = startLineParts[0];
  const requestTarget = startLineParts[1];
  const httpVersion = startLineParts[2];
  if (httpVersion !== "HTTP/1.1") {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest] Unsupported HTTP version: ${httpVersion}. Only HTTP/1.1 is supported.`);
    throw new Error("Unsupported HTTP version. Only HTTP/1.1 is supported.");
  }

  // 仅支持 GET 和 HEAD 方法
  if (method !== "GET" && method !== "HEAD") {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest] Unsupported HTTP method: ${method}. Only GET and HEAD are supported.`);
    throw new Error(`Unsupported HTTP method: ${method}. Only GET and HEAD are supported.`);
  }

  // 解析头部字段
  const headers: Record<string, string> = {};
  for (let i = 0; i < headerLines.length; i++) {
    const line = headerLines[i];
    const separatorIndex = line.indexOf(": ");
    if (separatorIndex === -1) {
      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest] Invalid header line: ${line}`);
      throw new Error(`Invalid header line: ${line}`);
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 2).trim();
    headers[key] = value;
  }

  // 验证 Host 头
  const host = headers["Host"];
  if (!host) {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest] Invalid HTTP/1.1 message: Missing 'Host' header.`);
    throw new Error("Invalid HTTP/1.1 message: Missing 'Host' header.");
  }

  MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpRequest] Successfully parsed request: Method=${method}, RequestTarget=${requestTarget}, Host=${host}`);

  return {
    method: method,
    requestTarget: requestTarget,
    host: host,
    headers: headers
  }
}