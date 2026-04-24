import axios from 'axios';
import { logger } from '../logger';
import { LlamaPool, YieldPool } from '../types';

const POOLS_URL = 'https://yields.llama.fi/pools';
const CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes

let poolsCache: LlamaPool[] | null = null;
let cacheTimestamp = 0;

export async function getAllPools(): Promise<LlamaPool[]> {
  const now = Date.now();
  if (poolsCache && now - cacheTimestamp < CACHE_TTL_MS) {
    return poolsCache;
  }

  logger.info({}, 'Fetching fresh pools from DeFiLlama');
  const res = await axios.get(POOLS_URL, { timeout: 15000 });
  const data = res.data as { status: string; data: LlamaPool[] };

  if (data.status !== 'success') {
    throw new Error('DeFiLlama API returned non-success status');
  }

  poolsCache = data.data;
  cacheTimestamp = now;
  logger.info({ count: poolsCache.length }, 'DeFiLlama pools cached');
  return poolsCache;
}

// Compute a simple risk score: higher TVL + no IL risk + established protocol = safer
const SAFE_PROTOCOLS = new Set([
  'aave-v3', 'aave-v2', 'compound-v3', 'compound-v2', 'morpho', 'morpho-blue',
  'spark', 'maker', 'curve', 'convex-finance', 'yearn-finance', 'uniswap-v3',
  'euler', 'fluid', 'sky', 'pendle',
]);

export function computeRiskScore(pool: LlamaPool): number {
  let score = 50;
  if (pool.tvlUsd > 100_000_000) score += 20;
  else if (pool.tvlUsd > 10_000_000) score += 10;
  else if (pool.tvlUsd < 1_000_000) score -= 20;

  if (pool.ilRisk === 'no' || pool.ilRisk === null) score += 10;
  else if (pool.ilRisk === 'yes') score -= 20;

  if (SAFE_PROTOCOLS.has(pool.project.toLowerCase())) score += 20;

  // Single-sided stablecoin pools are safer
  if (pool.stablecoin && !pool.symbol.includes('-')) score += 10;

  // Reward-only APY is riskier than base APY
  if (pool.apyReward && pool.apyReward > 0 && (!pool.apyBase || pool.apyBase < 0.5)) score -= 15;

  return Math.max(0, Math.min(100, score));
}

export function toYieldPool(pool: LlamaPool): YieldPool {
  return {
    pool: pool.pool,
    protocol: pool.project,
    chain: pool.chain,
    symbol: pool.symbol,
    apy: Math.round(pool.apy * 100) / 100,
    apyBase: pool.apyBase !== null ? Math.round(pool.apyBase * 100) / 100 : null,
    apyReward: pool.apyReward !== null ? Math.round(pool.apyReward * 100) / 100 : null,
    apyMean30d: pool.apyMean30d !== null ? Math.round(pool.apyMean30d * 100) / 100 : null,
    tvlUsd: Math.round(pool.tvlUsd),
    ilRisk: pool.ilRisk,
    poolMeta: pool.poolMeta || null,
    url: pool.url || null,
    riskScore: computeRiskScore(pool),
  };
}

export function filterStablecoinPools(
  pools: LlamaPool[],
  token: string,
  chain?: string,
  minTvl = 1_000_000
): LlamaPool[] {
  const tokenUpper = token.toUpperCase();
  return pools.filter((p) => {
    if (p.tvlUsd < minTvl) return false;
    if (p.apy <= 0 || p.apy > 300) return false; // filter outliers
    if (!p.symbol.toUpperCase().includes(tokenUpper)) return false;
    if (chain && p.chain.toLowerCase() !== chain.toLowerCase()) return false;
    return true;
  });
}
