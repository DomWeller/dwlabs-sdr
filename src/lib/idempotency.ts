export function buildIdempotencyKey(parts: string[]): string {
  return parts
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
    .join(":");
}

export class IdempotencyCache {
  private readonly seen = new Set<string>();

  public accept(key: string): boolean {
    if (this.seen.has(key)) {
      return false;
    }

    this.seen.add(key);
    return true;
  }
}
