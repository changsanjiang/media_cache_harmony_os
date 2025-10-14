/** 用于为虚拟代理提供数据; */
export interface IMCVirtualResource {
  /** MIME 类型, 默认 `application/octet-stream`; */
  readonly mimeType?: string;
}

/** 本地文件; */
export interface IMCVirtualResourceFile extends IMCVirtualResource {
  readonly filePath: string; // 本地文件路径
}

/** 内存 Buffer; */
export interface IMCVirtualResourceBuffer extends IMCVirtualResource {
  readonly buffer: ArrayBuffer; // 内存数据
}

/** 用于为虚拟代理提供数据; */
export type IMCVirtualResourceType = IMCVirtualResourceFile | IMCVirtualResourceBuffer;