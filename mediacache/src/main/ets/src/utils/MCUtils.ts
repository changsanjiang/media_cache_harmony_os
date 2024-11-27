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
}

export default MCUtils;