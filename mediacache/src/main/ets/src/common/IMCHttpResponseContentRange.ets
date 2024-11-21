import { IMCHttpRequestRange } from "./IMCHttpRequestRange";

/// https://datatracker.ietf.org/doc/html/rfc9110#field.content-range
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range#syntax
///
/// Content-Range: <unit> <range-start>-<range-end>/<size>
/// Content-Range: <unit> <range-start>-<range-end>/*
/// Content-Range: <unit> */<size>
export interface IMCHttpResponseContentRange {
  rangeStart?: number; // An integer in the given unit indicating the start position (zero-indexed & inclusive) of the request range.
  rangeEnd?: number; // An integer in the given unit indicating the end position (zero-indexed & inclusive) of the requested range.
  size?: number; // The total length of the document (or * if unknown).
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