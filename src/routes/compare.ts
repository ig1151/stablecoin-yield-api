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
