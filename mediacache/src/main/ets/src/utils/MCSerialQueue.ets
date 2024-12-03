export type MCAsyncCallback<T> = () => T | Promise<T>;

export class MCSerialQueue {
  private queue: Promise<void> = Promise.resolve();

  async enqueue<T>(callback: MCAsyncCallback<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      this.queue = this.queue.then(async () => {
        try {
          const result = await callback();
          resolve(result);
        } catch (err) {
          reject(err);
        }
      });
    });
  }
}