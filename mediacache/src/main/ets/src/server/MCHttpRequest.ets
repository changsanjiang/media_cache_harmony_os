import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { parseRequestRange } from "../defines/IMCHttpRequestRange";
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
  MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCHttpRequest][clientId: ${clientId}] Start parsing HTTP request with rawMessage: ${rawMessage}`);

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
  if (bodyPart.trim().length > 0) {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Request contains a body, which is not supported.`);
    throw new Error("Request contains a body, which is not supported.");
  }

  const headerLines = headerPart.split("\r\n");

  // 解析起始行
  const startLine = headerLines.shift();
  if (!startLine) {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Invalid HTTP message: Missing start line.`);
    throw new Error("Invalid HTTP message: Missing start line.");
  }

  // 分割起始行，获取 method, requestTarget, 和 httpVersion
  let startLineParts = startLine.split(" ");
  if (startLineParts.length !== 3) {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Invalid start line format: ${startLine}`);
    throw new Error(`Invalid start line format: ${startLine}`);
  }
  const method = startLineParts[0];
  const requestTarget = startLineParts[1];
  const httpVersion = startLineParts[2];
  if (httpVersion !== "HTTP/1.1") {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Unsupported HTTP version: ${httpVersion}. Only HTTP/1.1 is supported.`);
    throw new Error("Unsupported HTTP version. Only HTTP/1.1 is supported.");
  }

  // 仅支持 GET 和 HEAD 方法
  if (method !== "GET" && method !== "HEAD") {
    MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Unsupported HTTP method: ${method}. Only GET and HEAD are supported.`);
    throw new Error(`Unsupported HTTP method: ${method}. Only GET and HEAD are supported.`);
  }

  // 解析头部字段
  const headers: Map<string, string> = new Map();
  for (const line of headerLines) {
    const separatorIndex = line.indexOf(":");
    if (separatorIndex === -1) {
      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Invalid header line: ${line}`);
      throw new Error(`Invalid header line: ${line}`);
    }

    const key = line.slice(0, separatorIndex).trim().toLowerCase();
    const value = line.slice(separatorIndex + 2).trim();
    headers.set(key, value);
  }

  // // 验证 Host 头
  // const host = headers.get('host');
  // if (!host) {
  //   MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Invalid HTTP/1.1 message: Missing 'Host' header.`);
  //   throw new Error("Invalid HTTP/1.1 message: Missing 'Host' header.");
  // }

  // 验证 range 格式; 不支持多范围请求;
  const rangeHeader = headers.get('range');
  if (rangeHeader) {
    try {
      parseRequestRange(rangeHeader);
    }
    catch (e) {
      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpRequest][clientId: ${clientId}] Invalid Range format: ${rangeHeader}. Error: ${e.stack}`);
      throw new Error('Invalid Range format');
    }
  }

  MCConfigs.proxyRequestIgnoredHeaders.forEach((key) => {
    headers.delete(key);
  });

  const request: IMCHttpRequest = {
    method: method,
    requestTarget: requestTarget,
    headers: MCUtils.mapToRecord(headers)
  };

  MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpRequest][clientId: ${clientId}] Successfully parsed request: ${JSON.stringify(request)}`);

  return request
}