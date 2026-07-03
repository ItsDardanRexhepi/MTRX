# P2 Missing Routes — client legs awaiting a gateway handler

Recorded during **P1-2** (client `/api/v1` path correction). Each client method
below now targets the correct `/api/v1/...` namespace, but the gateway has no
handler registered for it yet. Until **P2 (Gateway route completion)** lands
these, the calls 404 and the owning view falls back to demo data — no fabricated
success (R10).

| Client method | Corrected client path | Backing service (if any) | P2 action |
|---|---|---|---|
| `OracleService.getAvailableFeeds` | `GET /api/v1/oracle/feeds` | oracle_gateway (feed catalog) | Register list-feeds route |
| `OracleService.getUserFeeds` | `GET /api/v1/oracle/feeds?address=` | oracle_gateway | Register per-wallet feed list |
| `OracleService.subscribeFeed` | `POST /api/v1/oracle/feeds/{id}/subscribe` | oracle_gateway | Register subscribe (through `_call`) |
| `OracleService.unsubscribeFeed` | `POST /api/v1/oracle/feeds/{id}/unsubscribe` | oracle_gateway | Register unsubscribe |
| `OracleService.getFeedHistory` | `GET /api/v1/oracle/feeds/{id}/history` | oracle_gateway `get_historical_price` | Register history route |
| `ComputeService.getComputeProviders` | `GET /api/v1/compute/providers` | — | Register provider catalog or honest not-implemented |
| `ComputeService.submitJob` | `POST /api/v1/compute/jobs` | `privacy.submit_compute_job` | Register job submit (through `_call`) |
| `ComputeService.getUserJobs` | `GET /api/v1/compute/jobs?address=` | — | Register job list |
| `ComputeService.getJobStatus` | `GET /api/v1/compute/jobs/{id}` | — | Register job status |
| `ComputeService.downloadResult` | `GET /api/v1/compute/jobs/{id}/result` | — | Register job result |
| `PortfolioService.getPerformanceHistory` | `GET /api/v1/portfolio/performance/{wallet}` | data_aggregator (needs perf series) | Register performance route |

## Already correct after P1-2 (route exists)

| Client method | Path | Gateway route |
|---|---|---|
| `PortfolioService.getPortfolioSummary` | `GET /api/v1/portfolio/complete/{wallet}` | ✅ registered |
| `PortfolioService.getTransactionHistory` | `GET /api/v1/portfolio/history/{wallet}` | ✅ registered |

> Note: `submitJob` and `subscribeFeed` must be registered through the gateway
> universal seam (`_call → gate_action`), same as every other route — see the
> P2 route-completion checklist.
