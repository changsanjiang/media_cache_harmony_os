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
}

export default MCArrayUtils;