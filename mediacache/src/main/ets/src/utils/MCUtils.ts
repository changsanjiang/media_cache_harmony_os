import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';

namespace MCUtils {
  export function objectToRecord<T>(obj: Object): Record<string, T> {
    let record: Record<string, T> = {};
    Object.entries(obj).forEach((kv: [string, Object]) => {
      let k = kv[0];
      let v = kv[1];
      record[k] = v as T;
    });
    return record;
  }

  // Map转为Record
  export function mapToRecord(map: Map<string, string>): Record<string, string> {
    return Object.fromEntries(map.entries()) as Record<string, string>;
  }

  // Record转为Map
  export function recordToMap(record: Record<string, string>): Map<string, string> {
    let myMap: Map<string, string> = new Map();
    for (const key in record) {
      myMap.set(key, record[key]);
    }
    return myMap;
  }

  export function modifyRecord(record: Record<string, string>, key: string, value?: string): Record<string, string> {
    let map = recordToMap(record);
    value != undefined ? map.set(key, value) : map.delete(key);
    return mapToRecord(map);
  }

  export async function hash(url: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new Uint8Array(buffer.from(url, 'utf-8').buffer) });
    const blob = await md.digest();
    return blob.data.slice(0, 16).reduce((str, byte) => str + byte.toString(16).padStart(2, '0'), '');
  }

  export function replaceCharactersInRange(str: string, range: [number, number], replacement: string): string {
    const [start, length] = range;

    // 检查范围是否合法
    if (start < 0 || length < 0 || start + length > str.length) {
      throw new Error("Invalid range");
    }

    // 截取字符串并拼接替换内容
    const before = str.slice(0, start); // 替换前部分
    const after = str.slice(start + length); // 替换后部分
    return before + replacement + after;
  }

  export function mergeArrayBuffers(buffer1: ArrayBuffer, buffer2: ArrayBuffer): ArrayBuffer {
    const mergedBuffer = new ArrayBuffer(buffer1.byteLength + buffer2.byteLength);
    const view = new Uint8Array(mergedBuffer);
    view.set(new Uint8Array(buffer1), 0);
    view.set(new Uint8Array(buffer2), buffer1.byteLength);
    return mergedBuffer;
  }
}

export default MCUtils;