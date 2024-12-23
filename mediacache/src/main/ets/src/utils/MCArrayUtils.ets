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
}

export default MCArrayUtils;