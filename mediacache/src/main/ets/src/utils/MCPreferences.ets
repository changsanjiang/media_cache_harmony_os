import { preferences } from '@kit.ArkData';
import MCUtils from './MCUtils';

export class MCPreferences<T extends preferences.ValueType> {
  private mPref: Promise<preferences.Preferences>;

  constructor(context: Context, name: string) {
    this.mPref = preferences.getPreferences(context, name);
  }

  has(key: string): Promise<boolean> {
    return this.mPref.then(p => p.has(key));
  }

  get(key: string, defValue: T): Promise<T> {
    return this.mPref.then(p => p.get(key, defValue) as T);
  }

  getValueOrUndefined(key: string): Promise<T | undefined> {
    return this.mPref.then(async (p) => {
      const has = await p.has(key);
      if ( has  ) {
        return p.get(key, {}) as T;
      }
      return undefined;
    });
  }

  getAll(): Promise<Record<string, T>> {
    return this.mPref.then(p => p.getAll()).then(all => MCUtils.objectToRecord(all));
  }

  set(key: string, value: T): Promise<void> {
    return this.mPref.then(p => p.put(key, value));
  }

  delete(key: string): Promise<void> {
    return this.mPref.then(p => p.delete(key));
  }

  flush(): Promise<void> {
    return this.mPref.then(p => p.flush());
  }
}