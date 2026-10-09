// Building RingDefs from a world seed: ring seeds and outer openings (entrances or arrivals).

import { arrivalOpenings, entranceOpenings } from './gates.js';
import { ringSeed } from './hash.js';
import type { RingDef, RingGenParams, RingShape } from './types.js';

export interface MakeRingDefArgs {
  worldSeed: number;
  ringIndex: number;
  shape: RingShape;
  params: RingGenParams;
  /** Ring 1 only. */
  entranceCount?: number;
  /** Ring >= 2: the previous ring's (frozen) generation params, which fix its gate slots. */
  prevParams?: RingGenParams;
}

export function makeRingDef(args: MakeRingDefArgs): RingDef {
  const { worldSeed, ringIndex, shape, params } = args;
  let outerOpenings;
  if (ringIndex === 1) {
    outerOpenings = entranceOpenings(args.entranceCount ?? 4);
  } else {
    if (!args.prevParams) throw new Error(`ring ${ringIndex} needs prevParams to place its arrivals`);
    outerOpenings = arrivalOpenings(ringSeed(worldSeed, ringIndex - 1), args.prevParams);
  }
  return { ringIndex, seed: ringSeed(worldSeed, ringIndex), shape, params, outerOpenings };
}
