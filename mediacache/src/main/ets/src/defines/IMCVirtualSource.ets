/** 数据源, 用于为虚拟代理提供数据; */
export interface IMCVirtualSource {
  /** MIME 类型, 默认 `application/octet-stream`; */
  readonly mimeType?: string;
}

/** 数据来源为本地文件; */
export interface IMCVirtualSourceFile extends IMCVirtualSource {
  readonly filePath: string; // 本地文件路径
}

/** 数据来源为内存 Buffer; */
export interface IMCVirtualSourceBuffer extends IMCVirtualSource {
  readonly buffer: ArrayBuffer; // 内存数据
}

/** 数据源, 用于为虚拟代理提供数据; */
export type IMCVirtualSourceType = IMCVirtualSourceFile | IMCVirtualSourceBuffer;