import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { parseRequestRange } from "../defines/IMCHttpRequestRange";
import { MCLogModule } from "../defines/MCLogModule";
import MCConfigs from "../utils/MCConfigs";
import MCLogger from "../utils/MCLogger";
import MCUtils from "../utils/MCUtils";

/**
 * 解析原始 HTTP 请求消息，仅处理 GET 和 HEAD 请求。
 *
 * @param rawMessage - 原始 HTTP 请求字符串
 * @returns IMCHttpRequest - 解析后的 HTTP 请求对象
 * @throws Error - 如果消息格式无效、不支持的 HTTP 方法或存在消息体，则抛出异常
 */
export function parseRequest(clientId: number, rawMessage: string): IMCHttpRequest {
  MCLogger.debug(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Start parsing HTTP request with rawMessage: \n${rawMessage}`);

  const delimiterIndex = rawMessage.indexOf("\r\n\r\n");
  const headerPart = delimiterIndex !== -1 ? rawMessage.slice(0, delimiterIndex) : rawMessage;

  const headerLines = headerPart.split("\r\n");

  // 解析起始行
  const startLine = headerLines.shift();
  if (!startLine) {
    MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Invalid HTTP message: Missing start line.`);
    throw new Error("Invalid HTTP message: Missing start line.");
  }

  // 分割起始行，获取 method, requestTarget, 和 httpVersion
  let startLineParts = startLine.split(" ");
  if (startLineParts.length !== 3) {
    MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Invalid start line format: ${startLine}`);
    throw new Error(`Invalid start line format: ${startLine}`);
  }
  const method = startLineParts[0];
  const requestTarget = startLineParts[1];
  const httpVersion = startLineParts[2];
  if (httpVersion !== "HTTP/1.1") {
    MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Unsupported HTTP version: ${httpVersion}. Only HTTP/1.1 is supported.`);
    throw new Error("Unsupported HTTP version. Only HTTP/1.1 is supported.");
  }

  // 仅支持 GET 和 HEAD 方法
  if (method !== "GET" && method !== "HEAD") {
    MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Unsupported HTTP method: ${method}. Only GET and HEAD are supported.`);
    throw new Error(`Unsupported HTTP method: ${method}. Only GET and HEAD are supported.`);
  }

  // 解析头部字段
  const headers: Map<string, string> = new Map();
  for (const line of headerLines) {
    const separatorIndex = line.indexOf(":");
    if (separatorIndex === -1) {
      MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Invalid header line: ${line}`);
      throw new Error(`Invalid header line: ${line}`);
    }

    const key = line.slice(0, separatorIndex).trim().toLowerCase();
    const value = line.slice(separatorIndex + 1).trim();
    headers.set(key, value);
  }

  // // 验证 Host 头
  // const host = headers.get('host');
  // if (!host) {
  //   MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Invalid HTTP/1.1 message: Missing 'Host' header.`);
  //   throw new Error("Invalid HTTP/1.1 message: Missing 'Host' header.");
  // }

  // 验证 range 格式; 不支持多范围请求;
  const rangeHeader = headers.get('range');
  if (rangeHeader) {
    try {
      parseRequestRange(rangeHeader);
    }
    catch (e) {
      MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Invalid Range format: ${rangeHeader}. Error: ${e.stack}`);
      throw new Error('Invalid Range format');
    }
  }

  const contentLengthHeader = headers.get('content-length');
  if (contentLengthHeader) {
    const contentLength = parseInt(contentLengthHeader, 10);
    if (!Number.isNaN(contentLength) && contentLength > 0) {
      MCLogger.error(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Request declares Content-Length ${contentLength}, body is not supported.`);
      throw new Error("Request contains a body, which is not supported.");
    }
  }

  MCConfigs.ignoredHeaders.forEach((key) => {
    headers.delete(key);
  });

  const request: IMCHttpRequest = {
    method: method,
    requestTarget: requestTarget,
    headers: MCUtils.mapToRecord(headers)
  };

  MCLogger.info(MCLogModule.MCHttpRequest, () => `[clientId: ${clientId}] Successfully parsed request: ${JSON.stringify(request)}`);

  return request
}