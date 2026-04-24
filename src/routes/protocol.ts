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
