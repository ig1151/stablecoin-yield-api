import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { validate } from '../middleware/validate';
import { getAllPools, filterStablecoinPools, toYieldPool } from '../services/defillama';
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

router.get('/', validate(bestYieldSchema), async (req: Request, res: Response): Promise<void> => {
  const { token, chain, riskTolerance } = req.query as {
    token: string; chain?: string; minTvl: string; riskTolerance: string;
  };
  const minTvlNum = parseFloat(req.query.minTvl as string) || 5000000;

  try {
    const allPools = await getAllPools();
    const filtered = filterStablecoinPools(allPools, token, chain, minTvlNum);
    const yieldPools = filtered.map(toYieldPool);
    yieldPools.sort((a, b) => b.apy - a.apy);
    const top20 = yieldPools.slice(0, 20);
    const highestApy = top20[0] || null;

    let riskWeight = 0.5;
    if (riskTolerance === 'low') riskWeight = 0.8;
    if (riskTolerance === 'high') riskWeight = 0.2;

    const scored = top20.map((p) => ({
      pool: p,
      score: p.apy * (1 - riskWeight) + p.riskScore * riskWeight,
    }));
    scored.sort((a, b) => b.score - a.score);
    const riskAdjustedBest = scored[0]?.pool || null;

    const poolSummary = top20.slice(0, 10).map((p) =>
      `${p.protocol} (${p.chain}) ${p.symbol}: APY ${p.apy}%, TVL $${(p.tvlUsd / 1e6).toFixed(1)}M, Risk score ${p.riskScore}/100${p.apyReward ? ` (includes ${p.apyReward}% reward APY)` : ''}`
    ).join('\n');

    const aiPrompt = `You are a DeFi yield strategist. A user wants the best ${token} yield with ${riskTolerance} risk tolerance${chain ? ` on ${chain}` : ' across all chains'}.

Here are the top pools by APY (min TVL $${(minTvlNum / 1e6).toFixed(0)}M):
${poolSummary}

Risk-adjusted recommendation: ${riskAdjustedBest ? `${riskAdjustedBest.protocol} at ${riskAdjustedBest.apy}% APY (risk score ${riskAdjustedBest.riskScore}/100)` : 'none'}
Highest raw APY: ${highestApy ? `${highestApy.protocol} at ${highestApy.apy}% APY` : 'none'}

Write 3 sentences: (1) what the current yield environment looks like for ${token}, (2) your top recommendation for ${riskTolerance} risk tolerance and why, (3) one key risk to watch. Be specific and direct.`;

    const aiRecommendation = await callAI(aiPrompt);

    const result: BestYieldResult = {
      token,
      chain: chain || null,
      minTvl: minTvlNum,
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