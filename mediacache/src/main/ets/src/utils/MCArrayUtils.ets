namespace MCArrayUtils {
  export function mapNotUndefined<T, U>(array: T[], block: (value: T, index: number, array: T[]) => U | undefined): U[] {
    const results = new Array<U>();
    array.forEach((value, index, array) => {
      const result = block(value, index, array);
      if ( result !== undefined ) {
        results.push(result);
      }
    });
    return results;
  }

  export function firstOrUndefined<T>(array: T[], block?: (value: T, index: number) => boolean): T | undefined {
    if ( block ) {
      let first: T | undefined = undefined;
      for (let i = 0; i < array.length; i++) {
        if ( block(array[i], i) ) {
          first = array[i];
          break;
        }
      }
      return first;
    }
    return array.length > 0 ? array[0] : undefined;
  }

  export function remove<T>(array: T[], element: T): number {
    const index = array.indexOf(element);
    if ( index >= 0 ) {
      array.splice(index, 1);
      return index;
    }
    return -1;
  }

  export function removeAt<T>(array: T[], index: number) {
    array.splice(index, 1);
  }

  export function add<T>(array: T[], value: T, index?: number): void {
    array.splice(Math.min(index ?? array.length, array.length), 0, value);
  }

  /** 根据key将元素分组; */
  export function groupByKey<K, V>(array: V[], keyProvider: (value: V, index: number) => K): Map<K, V[]> {
    return array.reduce((map, v, idx) => {
      const key = keyProvider(v, idx);
      const group = map.get(key);
      if ( group ) {
        group.push(v);
      }
      else {
        map.set(key, [v]);
      }
      return map;
    }, new Map<K, V[]>());
  }

  export function toMap<K, V>(array: V[], keyProvider: (value: V, index: number) => K): Map<K, V> {
    return array.reduce((map, v, idx) => {
      const key = keyProvider(v, idx);
      map.set(key, v);
      return map;
    }, new Map<K, V>());
  }
}

export default MCArrayUtils;