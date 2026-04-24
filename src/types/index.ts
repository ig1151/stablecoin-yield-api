export interface LlamaPool {
  pool: string;
  chain: string;
  project: string;
  symbol: string;
  tvlUsd: number;
  apy: number;
  apyBase: number | null;
  apyReward: number | null;
  apyMean30d: number | null;
  ilRisk: string | null;
  stablecoin: boolean;
  poolMeta: string | null;
  url: string | null;
}

export interface YieldPool {
  pool: string;
  protocol: string;
  chain: string;
  symbol: string;
  apy: number;
  apyBase: number | null;
  apyReward: number | null;
  apyMean30d: number | null;
  tvlUsd: number;
  ilRisk: string | null;
  poolMeta: string | null;
  url: string | null;
  riskScore: number; // 0-100, higher = safer
}

export interface BestYieldResult {
  token: string;
  chain: string | null;
  minTvl: number;
  topPools: YieldPool[];
  aiRecommendation: string;
  riskAdjustedBest: YieldPool | null;
  highestApy: YieldPool | null;
  analyzedAt: string;
}

export interface ProtocolSummary {
  protocol: string;
  totalTvlUsd: number;
  poolCount: number;
  chains: string[];
  avgApy: number;
  maxApy: number;
  minApy: number;
  stablecoinPools: YieldPool[];
  allPools: YieldPool[];
}

export interface CompareResult {
  token: string;
  protocols: Array<{
    protocol: string;
    bestPool: YieldPool | null;
    poolCount: number;
    totalTvlUsd: number;
    avgApy: number;
  }>;
  aiSummary: string;
  winner: string | null;
  analyzedAt: string;
}
