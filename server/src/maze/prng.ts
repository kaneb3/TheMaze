// mulberry32 PRNG with integer-only draws (spec §5.2).

const TWO_POW_32 = 4294967296;

export class Mulberry32 {
  private state: number;

  constructor(seed: number) {
    this.state = seed | 0;
  }

  /** Next uint32. */
  nextU32(): number {
    let t = (this.state = (this.state + 0x6d2b79f5) | 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  }

  /** Uniform integer in [0, n). Exact in doubles for n < 2^21. */
  randInt(n: number): number {
    return Math.floor((this.nextU32() * n) / TWO_POW_32);
  }

  /** True with probability permille / 1000. */
  chance(permille: number): boolean {
    return this.nextU32() % 1000 < permille;
  }
}
