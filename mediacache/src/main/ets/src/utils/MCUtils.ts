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
}

export default MCUtils;