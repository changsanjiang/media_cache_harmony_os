import { IMCHttpRequestRange, parseRequestRange } from "./IMCHttpRequestRange";

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
  // rangeStart, rangeEnd, size 必须有值
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

export function generateResponseContentRange(requestRange: IMCHttpRequestRange, totalLength: number): IMCHttpResponseContentRange {
  if ( totalLength <= 0 ) {
    throw new Error(`The total length must be greater than 0.`);
  }

  const requestRangeStart = requestRange.rangeStart;
  const requestRangeEnd = requestRange.rangeEnd;
  const requestSuffixLength = requestRange.suffixLength;

  // 检查范围合法性;
  if ( requestRangeStart && requestRangeStart >= totalLength ) {
    throw new Error('Invalid range: requestRangeStart exceeds total media length.');
  }
  if ( requestRangeEnd && requestRangeEnd >= totalLength ) {
    throw new Error('Invalid range: requestRangeEnd exceeds total media length.');
  }
  if ( requestSuffixLength && requestSuffixLength >= totalLength ) {
    throw new Error('Invalid range: requestSuffixLength exceeds total media length.');
  }

  // 转为 range;
  let rangeStart: number | undefined;
  let rangeEnd: number | undefined;

  if ( requestSuffixLength ) {
    rangeStart = totalLength - requestSuffixLength;
    rangeEnd = totalLength - 1;
  }
  else if ( requestRangeEnd ) {
    rangeStart = requestRangeStart!;
    rangeEnd = requestRangeEnd;
  }
  else {
    rangeStart = requestRangeStart!;
    rangeEnd = totalLength - 1;
  }

  return {
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    size: totalLength,
  }
}

export function toResponseContentRangeHeader(rangeStart: number, rangeEnd: number, totalLength: number): string {
  // 返回 Content-Range 字段
  return `bytes ${rangeStart}-${rangeEnd}/${totalLength}`;
}