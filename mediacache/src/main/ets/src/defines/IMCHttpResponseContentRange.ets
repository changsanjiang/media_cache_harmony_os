import { IMCHttpRequestRange } from "./IMCHttpRequestRange";

/// https://datatracker.ietf.org/doc/html/rfc9110#field.content-range
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range#syntax
///
/// Content-Range: <unit> <range-start>-<range-end>/<size>
/// Content-Range: <unit> <range-start>-<range-end>/*         // @note: unsupported
/// Content-Range: <unit> */<size>                            // @note: unsupported
export interface IMCHttpResponseContentRange {
  rangeStart: number; // An integer in the given unit indicating the start position (zero-indexed & inclusive) of the request range.
  rangeEnd: number; // An integer in the given unit indicating the end position (zero-indexed & inclusive) of the requested range.
  size: number; // The total length of the document (or * if unknown). // @note: unsupported `*`;
}

export function parseResponseContentRange(contentRangeHeader: string): IMCHttpResponseContentRange {
  // 检查单位是否为 bytes
  if (!contentRangeHeader.startsWith('bytes')) {
    throw new Error('Unsupported Content Range unit: Only "bytes" unit is supported');
  }

  // 匹配 Content-Range 的格式
  const matches = contentRangeHeader.match(/^bytes (\d+)-(\d+)\/(\d+)$/);
  if (!matches) {
    throw new Error('Invalid Content Range format. Expected format: bytes <range-start>-<range-end>/<size>');
  }

  const rangeStart: number | undefined = matches[1] ? parseInt(matches[1], 10) : undefined;
  const rangeEnd: number | undefined = matches[2] ? parseInt(matches[2], 10) : undefined;
  const size: number | undefined = matches[3] ? parseInt(matches[3], 10) : undefined;
  // 校验解析后的值
  if (rangeStart === undefined || rangeEnd === undefined || size === undefined) {
    throw new Error('Invalid Content Range format. range-start, range-end and size should be specified.');
  }

  if (isNaN(rangeStart) || isNaN(rangeEnd) || isNaN(size)) {
    throw new Error('Invalid Content Range values: range-start, range-end, and size must be integers.');
  }

  if (rangeStart > rangeEnd) {
    throw new Error('Invalid Content Range: range-start cannot be greater than range-end.');
  }

  if (rangeEnd >= size) {
    throw new Error('Invalid Content Range: range-end must be less than the total size.');
  }

  return {
    rangeStart,
    rangeEnd,
    size
  };
}


function generateContentRange(requestRange: IMCHttpRequestRange, fileSize: number): string {
  let rangeStart: number;
  let rangeEnd: number;

  // 处理 rangeStart 和 rangeEnd 的情况
  if (requestRange.rangeStart !== undefined && requestRange.rangeEnd !== undefined) {
    rangeStart = requestRange.rangeStart;
    rangeEnd = requestRange.rangeEnd;
  }
  // 只有 rangeStart，默认 rangeEnd 为文件末尾
  else if (requestRange.rangeStart !== undefined && requestRange.rangeEnd === undefined) {
    rangeStart = requestRange.rangeStart;
    rangeEnd = fileSize - 1;
  }
  // 只有 suffixLength，根据文件大小计算范围
  else if (requestRange.suffixLength !== undefined) {
    rangeStart = fileSize - Math.min(requestRange.suffixLength, fileSize);
    rangeEnd = fileSize - 1;
  }
  // 没有指定范围，返回整个文件
  else {
    rangeStart = 0;
    rangeEnd = fileSize - 1;
  }

  // 如果 rangeStart 大于 fileSize，返回整个文件的范围
  if (rangeStart >= fileSize) {
    rangeStart = 0;
    rangeEnd = fileSize - 1;
  }

  // 确保 rangeEnd 不超过文件大小
  if (rangeEnd >= fileSize) {
    rangeEnd = fileSize - 1;
  }

  // 返回 Content-Range 字段
  return `bytes ${rangeStart}-${rangeEnd}/${fileSize}`;
}