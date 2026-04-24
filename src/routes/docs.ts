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
