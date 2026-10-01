export type Ceiling = 'per-call-timeout';
export class CeilingReached extends Error {
  ceiling: Ceiling;
  constructor(ceiling: Ceiling) { super(`ceiling: ${ceiling}`); this.ceiling = ceiling; }
}

export const ceilings = { perCallMs: 10 * 60_000 };
