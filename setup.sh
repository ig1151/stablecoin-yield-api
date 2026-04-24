#!/bin/bash
set -e

echo "🔧 Setting up stablecoin-yield-api..."

# ── package.json ──────────────────────────────────────────────────────────────
cat > package.json << 'EOF'
{
  "name": "stablecoin-yield-api",
  "version": "1.0.0",
  "description": "Real-time stablecoin yield rates across DeFi protocols — powered by DeFiLlama + Claude AI",
  "main": "dist/index.js",
  "scripts": {
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "axios": "^1.7.2",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.3.1",
    "helmet": "^7.1.0",
    "joi": "^17.13.1"
  },
  "devDependencies": {
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.0",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.4.5"
  }
}
EOF

# ── tsconfig.json ─────────────────────────────────────────────────────────────
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
EOF

# ── render.yaml ───────────────────────────────────────────────────────────────
cat > render.yaml << 'EOF'
services:
  - type: web
    name: stablecoin-yield-api
    env: node
    buildCommand: npm install && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /v1/health
    envVars:
      - key: NODE_ENV
        value: production
      - key: PORT
        value: 3000
      - key: OPENROUTER_API_KEY
        sync: false
EOF

# ── .gitignore ────────────────────────────────────────────────────────────────
cat > .gitignore << 'EOF'
node_modules/
dist/
.env
*.log
EOF

# ── .env.example ─────────────────────────────────────────────────────────────
cat > .env.example << 'EOF'
PORT=3000
NODE_ENV=development
OPENROUTER_API_KEY=your_openrouter_api_key
EOF

# ── src/ structure ────────────────────────────────────────────────────────────
mkdir -p src/routes src/services src/middleware src/types

# ── src/logger.ts ─────────────────────────────────────────────────────────────
cat > src/logger.ts << 'EOF'
export const logger = {
  info: (obj: unknown, msg?: string) =>
    console.log(JSON.stringify({ level: 'info', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  warn: (obj: unknown, msg?: string) =>
    console.warn(JSON.stringify({ level: 'warn', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  error: (obj: unknown, msg?: string) =>
    console.error(JSON.stringify({ level: 'error', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
};
EOF

# ── src/types/index.ts ────────────────────────────────────────────────────────
cat > src/types/index.ts << 'EOF'
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
EOF

# ── src/services/defillama.ts ─────────────────────────────────────────────────
cat > src/services/defillama.ts << 'EOF'
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
EOF

# ── src/services/ai.ts ────────────────────────────────────────────────────────
cat > src/services/ai.ts << 'EOF'
import axios from 'axios';

type Messages = string | { role: string; content: string }[];

export async function callAI(input: Messages, systemPrompt?: string): Promise<string> {
  const messages: { role: string; content: string }[] = typeof input === 'string'
    ? [{ role: 'user', content: input }]
    : input;

  const body: Record<string, unknown> = {
    model: 'anthropic/claude-sonnet-4-5',
    max_tokens: 1000,
    messages,
  };
  if (systemPrompt) body.system = systemPrompt;

  const res = await axios.post(
    'https://openrouter.ai/api/v1/chat/completions',
    body,
    {
      headers: {
        Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
      },
      timeout: 20000,
    }
  );

  const data = res.data as { choices: { message: { content: string } }[] };
  return data.choices[0].message.content;
}
EOF

# ── src/middleware/validate.ts ────────────────────────────────────────────────
cat > src/middleware/validate.ts << 'EOF'
import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';

export function validate(schema: Joi.ObjectSchema) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const { error } = schema.validate(req.query);
    if (error) {
      res.status(400).json({
        error: 'Validation error',
        details: error.details.map((d) => d.message),
      });
      return;
    }
    next();
  };
}
EOF

# ── src/routes/health.ts ──────────────────────────────────────────────────────
cat > src/routes/health.ts << 'EOF'
import { Router, Request, Response } from 'express';

const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'stablecoin-yield-api',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

export default router;
EOF

# ── src/routes/rates.ts ───────────────────────────────────────────────────────
cat > src/routes/rates.ts << 'EOF'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { getAllPools, filterStablecoinPools, toYieldPool } from '../services/defillama';
import { logger } from '../logger';

const router = Router();

const ratesSchema = Joi.object({
  token: Joi.string().uppercase().default('USDC'),
  chain: Joi.string().optional(),
  minTvl: Joi.number().min(0).default(1000000),
  sortBy: Joi.string().valid('apy', 'tvl', 'risk').default('apy'),
  limit: Joi.number().min(1).max(50).default(10),
});

// GET /v1/rates
router.get('/', validate(ratesSchema), async (req: Request, res: Response): Promise<void> => {
  const { token, chain, minTvl, sortBy, limit } = req.query as {
    token: string;
    chain?: string;
    minTvl: string;
    sortBy: string;
    limit: string;
  };

  try {
    const allPools = await getAllPools();
    const filtered = filterStablecoinPools(allPools, token, chain, parseFloat(minTvl));
    const yieldPools = filtered.map(toYieldPool);

    // Sort
    if (sortBy === 'apy') {
      yieldPools.sort((a, b) => b.apy - a.apy);
    } else if (sortBy === 'tvl') {
      yieldPools.sort((a, b) => b.tvlUsd - a.tvlUsd);
    } else if (sortBy === 'risk') {
      yieldPools.sort((a, b) => b.riskScore - a.riskScore);
    }

    const results = yieldPools.slice(0, parseInt(limit));

    const avgApy = results.length
      ? Math.round((results.reduce((s, p) => s + p.apy, 0) / results.length) * 100) / 100
      : 0;

    logger.info({ token, chain, count: results.length, sortBy }, 'rates');
    res.json({
      success: true,
      data: {
        token,
        chain: chain || 'all',
        minTvlUsd: parseFloat(minTvl),
        totalPoolsFound: filtered.length,
        avgApy,
        sortBy,
        pools: results,
        cachedAt: new Date().toISOString(),
      },
    });
  } catch (err: any) {
    logger.error({ err: err.message }, 'rates error');
    res.status(500).json({ error: 'Failed to fetch yield rates', details: err.message });
  }
});

export default router;
EOF

# ── src/routes/bestYield.ts ───────────────────────────────────────────────────
cat > src/routes/bestYield.ts << 'EOF'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { getAllPools, filterStablecoinPools, toYieldPool, computeRiskScore } from '../services/defillama';
import { callAI } from '../services/ai';
import { logger } from '../logger';
import { BestYieldResult, YieldPool } from '../types';

const router = Router();

const bestYieldSchema = Joi.object({
  token: Joi.string().uppercase().default('USDC'),
  chain: Joi.string().optional(),
  minTvl: Joi.number().min(0).default(5000000),
  riskTolerance: Joi.string().valid('low', 'medium', 'high').default('medium'),
});

// GET /v1/best-yield
router.get('/', validate(bestYieldSchema), async (req: Request, res: Response): Promise<void> => {
  const { token, chain, minTvl, riskTolerance } = req.query as {
    token: string;
    chain?: string;
    minTvl: string;
    riskTolerance: string;
  };

  try {
    const allPools = await getAllPools();
    const filtered = filterStablecoinPools(allPools, token, chain, parseFloat(minTvl));
    const yieldPools = filtered.map(toYieldPool);

    // Sort by APY descending, take top 20 for AI context
    yieldPools.sort((a, b) => b.apy - a.apy);
    const top20 = yieldPools.slice(0, 20);

    // Highest APY
    const highestApy = top20[0] || null;

    // Risk-adjusted best: weight APY * riskScore
    let riskWeight = 0.5;
    if (riskTolerance === 'low') riskWeight = 0.8;
    if (riskTolerance === 'high') riskWeight = 0.2;

    const scored = top20.map((p) => ({
      pool: p,
      score: p.apy * (1 - riskWeight) + p.riskScore * riskWeight,
    }));
    scored.sort((a, b) => b.score - a.score);
    const riskAdjustedBest = scored[0]?.pool || null;

    // Build AI context
    const poolSummary = top20
      .slice(0, 10)
      .map(
        (p) =>
          `${p.protocol} (${p.chain}) ${p.symbol}: APY ${p.apy}%, TVL $${(p.tvlUsd / 1e6).toFixed(1)}M, Risk score ${p.riskScore}/100${p.apyReward ? ` (includes ${p.apyReward}% reward APY)` : ''}`
      )
      .join('\n');

    const aiPrompt = `You are a DeFi yield strategist. A user wants the best ${token} yield with ${riskTolerance} risk tolerance${chain ? ` on ${chain}` : ' across all chains'}.

Here are the top pools by APY (min TVL $${(parseFloat(minTvl) / 1e6).toFixed(0)}M):
${poolSummary}

Risk-adjusted recommendation: ${riskAdjustedBest ? `${riskAdjustedBest.protocol} at ${riskAdjustedBest.apy}% APY (risk score ${riskAdjustedBest.riskScore}/100)` : 'none'}
Highest raw APY: ${highestApy ? `${highestApy.protocol} at ${highestApy.apy}% APY` : 'none'}

Write 3 sentences: (1) what the current yield environment looks like for ${token}, (2) your top recommendation for ${riskTolerance} risk tolerance and why, (3) one key risk to watch. Be specific and direct.`;

    const aiRecommendation = await callAI(aiPrompt);

    const result: BestYieldResult = {
      token,
      chain: chain || null,
      minTvl: parseFloat(minTvl),
      topPools: top20.slice(0, 5),
      aiRecommendation,
      riskAdjustedBest,
      highestApy,
      analyzedAt: new Date().toISOString(),
    };

    logger.info({ token, chain, riskTolerance, topApy: highestApy?.apy }, 'best-yield');
    res.json({ success: true, data: result });
  } catch (err: any) {
    logger.error({ err: err.message }, 'best-yield error');
    res.status(500).json({ error: 'Failed to compute best yield', details: err.message });
  }
});

export default router;
EOF

# ── src/routes/protocol.ts ────────────────────────────────────────────────────
cat > src/routes/protocol.ts << 'EOF'
import { Router, Request, Response } from 'express';
import { getAllPools, toYieldPool } from '../services/defillama';
import { logger } from '../logger';
import { ProtocolSummary } from '../types';

const router = Router();

// GET /v1/protocol/:name
router.get('/:name', async (req: Request, res: Response): Promise<void> => {
  const { name } = req.params;

  try {
    const allPools = await getAllPools();
    const protocolPools = allPools.filter(
      (p) => p.project.toLowerCase() === name.toLowerCase()
    );

    if (protocolPools.length === 0) {
      res.status(404).json({
        error: `Protocol "${name}" not found`,
        hint: 'Use the DeFiLlama slug (e.g. aave-v3, compound-v3, morpho-blue)',
      });
      return;
    }

    const yieldPools = protocolPools
      .filter((p) => p.apy > 0 && p.apy < 300)
      .map(toYieldPool)
      .sort((a, b) => b.apy - a.apy);

    const stablecoinPools = yieldPools.filter((p) => p.symbol.match(/USDC|USDT|DAI|FRAX|LUSD|PYUSD|GHO/i));

    const chains = [...new Set(yieldPools.map((p) => p.chain))];
    const totalTvl = protocolPools.reduce((s, p) => s + (p.tvlUsd || 0), 0);
    const apys = yieldPools.map((p) => p.apy);
    const avgApy = apys.length
      ? Math.round((apys.reduce((s, a) => s + a, 0) / apys.length) * 100) / 100
      : 0;

    const result: ProtocolSummary = {
      protocol: name.toLowerCase(),
      totalTvlUsd: Math.round(totalTvl),
      poolCount: yieldPools.length,
      chains,
      avgApy,
      maxApy: apys.length ? Math.max(...apys) : 0,
      minApy: apys.length ? Math.min(...apys) : 0,
      stablecoinPools: stablecoinPools.slice(0, 10),
      allPools: yieldPools.slice(0, 20),
    };

    logger.info({ protocol: name, poolCount: yieldPools.length }, 'protocol');
    res.json({ success: true, data: result });
  } catch (err: any) {
    logger.error({ err: err.message, protocol: name }, 'protocol error');
    res.status(500).json({ error: 'Failed to fetch protocol data', details: err.message });
  }
});

export default router;
EOF

# ── src/routes/compare.ts ─────────────────────────────────────────────────────
cat > src/routes/compare.ts << 'EOF'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { getAllPools, toYieldPool } from '../services/defillama';
import { callAI } from '../services/ai';
import { logger } from '../logger';
import { CompareResult } from '../types';

const router = Router();

const compareSchema = Joi.object({
  token: Joi.string().uppercase().default('USDC'),
  protocols: Joi.string().required(), // comma-separated, e.g. "aave-v3,compound-v3,morpho-blue"
  chain: Joi.string().optional(),
});

// GET /v1/compare
router.get('/', validate(compareSchema), async (req: Request, res: Response): Promise<void> => {
  const { token, protocols, chain } = req.query as {
    token: string;
    protocols: string;
    chain?: string;
  };

  const protocolList = protocols
    .split(',')
    .map((p) => p.trim().toLowerCase())
    .slice(0, 4); // max 4

  try {
    const allPools = await getAllPools();

    const results = protocolList.map((protocol) => {
      const protocolPools = allPools.filter(
        (p) =>
          p.project.toLowerCase() === protocol &&
          p.symbol.toUpperCase().includes(token) &&
          p.apy > 0 &&
          p.apy < 300 &&
          p.tvlUsd > 100_000 &&
          (!chain || p.chain.toLowerCase() === chain.toLowerCase())
      );

      const yieldPools = protocolPools.map(toYieldPool).sort((a, b) => b.apy - a.apy);
      const bestPool = yieldPools[0] || null;
      const totalTvl = protocolPools.reduce((s, p) => s + p.tvlUsd, 0);
      const avgApy =
        yieldPools.length
          ? Math.round((yieldPools.reduce((s, p) => s + p.apy, 0) / yieldPools.length) * 100) / 100
          : 0;

      return {
        protocol,
        bestPool,
        poolCount: yieldPools.length,
        totalTvlUsd: Math.round(totalTvl),
        avgApy,
      };
    });

    // Find winner by best APY
    const withPools = results.filter((r) => r.bestPool !== null);
    const winner = withPools.length
      ? withPools.sort((a, b) => (b.bestPool?.apy || 0) - (a.bestPool?.apy || 0))[0].protocol
      : null;

    // AI summary
    const comparison = results
      .map(
        (r) =>
          `${r.protocol}: best APY ${r.bestPool?.apy ?? 'N/A'}%, TVL $${(r.totalTvlUsd / 1e6).toFixed(1)}M, risk score ${r.bestPool?.riskScore ?? 'N/A'}/100`
      )
      .join('\n');

    const aiPrompt = `Compare these DeFi protocols for ${token} yield${chain ? ` on ${chain}` : ''}:

${comparison}

Write 2 sentences: (1) which protocol offers the best balance of yield and safety and why, (2) when you'd choose each option. Be specific.`;

    const aiSummary = await callAI(aiPrompt);

    const result: CompareResult = {
      token,
      protocols: results,
      aiSummary,
      winner,
      analyzedAt: new Date().toISOString(),
    };

    logger.info({ token, protocols: protocolList, winner }, 'compare');
    res.json({ success: true, data: result });
  } catch (err: any) {
    logger.error({ err: err.message }, 'compare error');
    res.status(500).json({ error: 'Failed to compare protocols', details: err.message });
  }
});

export default router;
EOF

# ── src/routes/docs.ts ────────────────────────────────────────────────────────
cat > src/routes/docs.ts << 'EOF'
import { Router, Request, Response } from 'express';

const router = Router();

const openApiSpec = {
  openapi: '3.0.0',
  info: {
    title: 'Stablecoin Yield API',
    version: '1.0.0',
    description:
      'Real-time stablecoin yield rates across DeFi protocols. Compare APYs, get AI-powered allocation recommendations, and analyze protocols. Powered by DeFiLlama + Claude AI. No API key required for data source.',
    contact: { url: 'https://orbisapi.com' },
  },
  servers: [{ url: 'https://stablecoin-yield-api.onrender.com' }],
  paths: {
    '/v1/health': {
      get: { summary: 'Health check', responses: { 200: { description: 'OK' } } },
    },
    '/v1/rates': {
      get: {
        summary: 'Live stablecoin yield rates — sorted by APY, TVL, or risk score',
        operationId: 'getRates',
        parameters: [
          { name: 'token', in: 'query', schema: { type: 'string', default: 'USDC' }, description: 'Token symbol (USDC, USDT, DAI, etc.)' },
          { name: 'chain', in: 'query', schema: { type: 'string' }, description: 'Filter by chain (Ethereum, Base, Arbitrum, etc.)' },
          { name: 'minTvl', in: 'query', schema: { type: 'number', default: 1000000 }, description: 'Minimum pool TVL in USD' },
          { name: 'sortBy', in: 'query', schema: { type: 'string', enum: ['apy', 'tvl', 'risk'], default: 'apy' } },
          { name: 'limit', in: 'query', schema: { type: 'number', default: 10 } },
        ],
        responses: { 200: { description: 'List of yield pools with APY, TVL, risk score' } },
      },
    },
    '/v1/best-yield': {
      get: {
        summary: 'AI-powered best yield recommendation with risk-adjusted allocation',
        operationId: 'getBestYield',
        parameters: [
          { name: 'token', in: 'query', schema: { type: 'string', default: 'USDC' } },
          { name: 'chain', in: 'query', schema: { type: 'string' } },
          { name: 'minTvl', in: 'query', schema: { type: 'number', default: 5000000 } },
          { name: 'riskTolerance', in: 'query', schema: { type: 'string', enum: ['low', 'medium', 'high'], default: 'medium' } },
        ],
        responses: { 200: { description: 'AI recommendation with top pools, risk-adjusted best, highest APY' } },
      },
    },
    '/v1/protocol/{name}': {
      get: {
        summary: 'All yield pools for a specific protocol with stats summary',
        operationId: 'getProtocol',
        parameters: [
          { name: 'name', in: 'path', required: true, schema: { type: 'string' }, description: 'DeFiLlama protocol slug (e.g. aave-v3, compound-v3, morpho-blue)' },
        ],
        responses: { 200: { description: 'Protocol summary with all pools, TVL, APY stats' } },
      },
    },
    '/v1/compare': {
      get: {
        summary: 'Side-by-side protocol comparison for a given token with AI summary',
        operationId: 'compareProtocols',
        parameters: [
          { name: 'token', in: 'query', schema: { type: 'string', default: 'USDC' } },
          { name: 'protocols', in: 'query', required: true, schema: { type: 'string' }, description: 'Comma-separated protocol slugs (e.g. aave-v3,compound-v3,morpho-blue)' },
          { name: 'chain', in: 'query', schema: { type: 'string' } },
        ],
        responses: { 200: { description: 'Side-by-side comparison with AI winner analysis' } },
      },
    },
  },
};

router.get('/openapi.json', (_req: Request, res: Response) => {
  res.json(openApiSpec);
});

router.get('/docs', (_req: Request, res: Response) => {
  res.send(`<!DOCTYPE html>
<html>
<head>
  <title>Stablecoin Yield API — Docs</title>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" type="text/css" href="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.11.0/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/5.11.0/swagger-ui-bundle.js"></script>
<script>
  SwaggerUIBundle({
    url: '/openapi.json',
    dom_id: '#swagger-ui',
    presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
    layout: 'BaseLayout'
  });
</script>
</body>
</html>`);
});

export default router;
EOF

# ── src/index.ts ──────────────────────────────────────────────────────────────
cat > src/index.ts << 'EOF'
import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { logger } from './logger';
import healthRouter from './routes/health';
import ratesRouter from './routes/rates';
import bestYieldRouter from './routes/bestYield';
import protocolRouter from './routes/protocol';
import compareRouter from './routes/compare';
import docsRouter from './routes/docs';

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());

const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});
app.use(limiter);

app.use('/v1/health', healthRouter);
app.use('/v1/rates', ratesRouter);
app.use('/v1/best-yield', bestYieldRouter);
app.use('/v1/protocol', protocolRouter);
app.use('/v1/compare', compareRouter);
app.use('/', docsRouter);

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.listen(PORT, () => {
  logger.info({ port: PORT }, 'stablecoin-yield-api started');
});

export default app;
EOF

echo ""
echo "✅ stablecoin-yield-api scaffold complete!"
echo ""
echo "Next steps:"
echo "  1. npm install"
echo "  2. cp .env.example .env && add OPENROUTER_API_KEY"
echo "  3. npm run dev"
echo ""
echo "Endpoints:"
echo "  GET /v1/health"
echo "  GET /v1/rates?token=USDC&chain=Ethereum&sortBy=apy"
echo "  GET /v1/best-yield?token=USDC&riskTolerance=medium    (AI)"
echo "  GET /v1/protocol/aave-v3"
echo "  GET /v1/compare?token=USDC&protocols=aave-v3,compound-v3,morpho-blue  (AI)"
echo "  GET /docs"
echo "  GET /openapi.json"
