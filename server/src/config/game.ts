// ALL gameplay tunables live here (spec §0.3, §15). Never hard-code gameplay numbers elsewhere.

import type { RingGenParams } from '../maze/types.js';

export const game = {
  // World & units
  cellSizeM: 4,
  wallHeightM: 7,
  chunkSize: 32, // don't change after launch
  tickHz: 20,
  stateHz: 10,
  visibilityHz: 5,

  // Movement (spec §7; mirrored by client/player/locomotion.gd until the client receives these in `welcome`)
  walkSpeed: 2.5, // m/s
  strafeMultiplier: 0.8,
  backMultiplier: 0.7,
  sprintMultiplier: 1.8,
  sprintMinForward: 0.7, // forward share of the wish direction needed to sprint
  sprintStaminaS: 6,
  sprintRegenDelayS: 1,
  sprintRegenRate: 0.75, // stamina seconds per second
  sprintResumeS: 1.5,
  accelPush: 18, // m/s^2 from standing, easing to accelWalk at walk speed
  accelWalk: 7,
  accelSprint: 4.5,
  moveDrag: 7, // 1/s
  moveBrake: 5, // m/s^2
  runBrake: 11, // m/s^2 above walk speed
  moveSubstepHz: 60,
  cartSpeedMultiplier: 0.6,
  darkSpeedMultiplier: 0.5,
  playerRadiusM: 0.4,

  // Light
  lanternRadiusCells: 6,
  maxLightRadiusCells: 12,
  campLightRadiusCells: 5,

  // Oil
  lanternTankCap: 10,
  packCap: 20,
  lanternPlaceCost: 5,
  placedLanternRadius: 4,
  lanternUpkeepPerHour: 0.1,
  campBuildCost: 50,
  campCapacity: 1000,
  campUpkeepPerHour: 1.0,
  campServiceRadius: 32, // cells, Euclidean
  campMinSpacing: 48, // cells
  campWithdrawLimitPerHour: 20, // base; never below packCap
  campWithdrawTrustMaxMultiplier: 5,
  deliveryWindowHours: 6,
  hubInitialStock: 300,
  cacheOilMin: 20,
  cacheOilMax: 60,
  supplyRequestHours: 24,

  // Carts
  cartCost: 10,
  cartCapacity: 200,
  cartAbandonHours: 72,

  // Tools
  flareCost: 3,
  flareRadius: 6,
  flareSeconds: 60,
  periscopeSeconds: 5,
  periscopeRadius: 10,
  bellCost: 10,
  bellPathRange: 40,
  signpostCost: 2,
  markerFadeDays: 7,
  chalkPerPlayer: 200,
  leadClaimHours: 2,
  districtNamingThreshold: 0.9,
  pingRadiusCells: 64,
  pingSeconds: 300,

  // Generation feature gates
  plateMinRing: 3,
  entranceCount: 4,

  // Rings & pacing
  plannedRingCount: 5,
  ringTargetDays: 21,
  lockLeadDays: 7,
  ringMinChunks: 64,
  ringMaxChunks: 200_000,
  ringThicknessRatio: 0.25,
  ringThicknessRatioMin: 0.15,
  ringThicknessRatioMax: 0.5,
  fInitial: 0.4,

  // Finale
  kindlingTargetDays: 10,
  kindlingFactor: 0.8,
  lighthouseOilMin: 5000,
  lighthouseOilMax: 5_000_000,
  ignitionDelayMinutes: 30,
  ignitionWaveSeconds: 300,

  // Server
  streamRadiusChunks: 2,
  chunkCacheSize: 20_000,
  losCacheSize: 200_000,
  persistIntervalSec: 5,

  // Rate limits (per player)
  rateLimits: {
    chalkPerHour: 30,
    notesPerHour: 10,
    markersPerHour: 30,
    signpostsPerHour: 10,
    votesPerHour: 120,
    pingsPerHour: 20,
    quickChatMinIntervalSec: 3,
  },
} as const;

/** Default generation params for a new ring. Frozen into the ring row when it is locked. */
export function defaultRingGenParams(ringIndex: number): RingGenParams {
  return {
    newestBiasPermille: 750,
    narrowPermille: ringIndex >= 2 ? 150 : 0,
    leverPermille: 15,
    leverMinTreeDistance: 40,
    coarseLeverPermille: 200,
    platePermille: ringIndex >= game.plateMinRing ? 80 : 0,
    plateMaxDistanceCells: 6,
    gateSlotCount: 12,
    gateCount: 5,
  };
}

/** Vertical slice (spec §16.0): one ring + the Core, with every generation feature enabled. */
export const slice = {
  plannedRingCount: 1,
  ringShape: { outerHalf: 4, innerHalf: 2 },
  lighthouseOil: 2000,
} as const;

export function sliceRingGenParams(): RingGenParams {
  return { ...defaultRingGenParams(1), narrowPermille: 150, platePermille: 80 };
}

/** Per-ring parameters that stay tunable live (spec §10.7). */
export interface RingLiveParams {
  ambientRadiusCells: number;
  cacheDensityPermille: number;
  lanternBurnPerMin: number;
}

export function defaultRingLiveParams(ringIndex: number): RingLiveParams {
  return {
    ambientRadiusCells: ringIndex === 1 ? 2 : 0,
    cacheDensityPermille: 250,
    lanternBurnPerMin: 1.0,
  };
}
