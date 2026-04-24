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
  sortBy: Joi.string().valid('apy', 'tvl', 'risk').default('risk'),
  limit: Joi.number().min(1).max(50).default(10),
});

router.get('/', validate(ratesSchema), async (req: Request, res: Response): Promise<void> => {
  const { token, chain, sortBy, limit } = req.query as {
    token: string; chain?: string; minTvl: string; sortBy: string; limit: string;
  };
  const minTvlNum = parseFloat(req.query.minTvl as string) || 1000000;

  try {
    const allPools = await getAllPools();
    const filtered = filterStablecoinPools(allPools, token, chain, minTvlNum);
    const yieldPools = filtered.map(toYieldPool);

    if (sortBy === 'apy') yieldPools.sort((a, b) => b.apy - a.apy);
    else if (sortBy === 'tvl') yieldPools.sort((a, b) => b.tvlUsd - a.tvlUsd);
    else yieldPools.sort((a, b) => b.riskScore - a.riskScore);

    const results = yieldPools.slice(0, parseInt(limit as string));
    const avgApy = results.length
      ? Math.round((results.reduce((s, p) => s + p.apy, 0) / results.length) * 100) / 100
      : 0;

    logger.info({ token, chain, count: results.length, sortBy }, 'rates');
    res.json({
      success: true,
      data: {
        token,
        chain: chain || 'all',
        minTvlUsd: minTvlNum,
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