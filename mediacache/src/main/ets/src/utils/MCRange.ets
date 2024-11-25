export class MCRange {
  static zero = new MCRange(0, 0);

  location: number;
  length: number;

  constructor(location: number, length: number) {
    if (length < 0) {
      throw new Error("Length cannot be negative");
    }
    this.location = location;
    this.length = length;
  }

  get max(): number {
    return this.location + this.length;
  }

  toString(): string {
    return `[MCRange: location=${this.location}, length=${this.length}]`;
  }

  contains(sub: MCRange): boolean {
    return this.location <= sub.location && this.location + this.length >= sub.location + sub.length;
  }

  isIntersecting(other: MCRange): boolean {
    return this.intersection(other) !== undefined;
  }

  intersection(other: MCRange): MCRange | undefined {
    const maxStart = Math.max(this.location, other.location);
    const minEnd = Math.min(this.max, other.max);
    if (maxStart < minEnd) { // 存在交集时，交集长度必须大于 0
      return new MCRange(maxStart, minEnd - maxStart);
    }
    return undefined;
  }
}