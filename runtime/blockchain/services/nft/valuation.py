"""
NFT Valuation Engine — Component 3

Provides 90-day valuation assessment for NFTs minted on the OpenMatrix platform.
Uses Component 11 oracle interface for ALL price feeds (NEVER direct Chainlink calls).

Lifecycle:
    1. schedule_90_day_assessment(nft_id) — called at mint time
    2. After 90 days: assess_value(nft_id) — computes valuation
    3. trigger_payment_window(nft_id) — opens 7-day payment window
    4. If unpaid after 7 days: rights revert via NFTRights.sol

NeoSafe: 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

from web3 import Web3
from web3.contract import Contract

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────
#  Constants
# ──────────────────────────────────────────────

NEOSAFE_ADDRESS = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
VALUATION_PERIOD_DAYS = 90
PAYMENT_WINDOW_DAYS = 7
PAYMENT_PERCENTAGE = Decimal("0.10")  # 10% of assessed value


class ValuationMethodology(str, Enum):
    """How the valuation was determined."""
    SECONDARY_MARKET = "secondary_market_trading"
    COMPARABLE_COLLECTION = "comparable_collection_floor"
    MINT_VALUE_FALLBACK = "original_mint_value"
    HYBRID = "hybrid_weighted_average"


class AssessmentStatus(str, Enum):
    """Status of a valuation assessment."""
    SCHEDULED = "scheduled"
    PENDING = "pending"
    ASSESSED = "assessed"
    PAYMENT_WINDOW_OPEN = "payment_window_open"
    PAYMENT_RECEIVED = "payment_received"
    RIGHTS_REVERTED = "rights_reverted"
    EXPIRED = "expired"


# ──────────────────────────────────────────────
#  Data Classes
# ──────────────────────────────────────────────

@dataclass
class TradingActivity:
    """Aggregated trading activity for an NFT over its lifetime."""
    nft_id: int
    total_sales: int
    total_volume_wei: int
    total_volume_usd: Decimal
    average_sale_price_wei: int
    average_sale_price_usd: Decimal
    highest_sale_wei: int
    lowest_sale_wei: int
    last_sale_wei: int
    last_sale_timestamp: Optional[datetime]
    unique_owners: int
    sales_history: List[Dict[str, Any]] = field(default_factory=list)

    @property
    def has_secondary_trading(self) -> bool:
        """Whether this NFT has any recorded secondary market sales."""
        return self.total_sales > 0


@dataclass
class PriceFeedData:
    """Price feed data from Component 11 oracle interface."""
    pair: str               # e.g., "ETH/USD"
    price: Decimal          # Current price
    decimals: int           # Price feed decimals
    updated_at: datetime    # Last update timestamp
    round_id: int           # Oracle round ID
    source: str             # "component_11_oracle" — never "chainlink_direct"


@dataclass
class ValuationResult:
    """Complete valuation result for an NFT at the 90-day assessment mark."""
    nft_id: int
    assessed_value_wei: int
    assessed_value_usd: Decimal
    methodology: ValuationMethodology
    trading_data: Optional[TradingActivity]
    assessment_date: datetime
    confidence_score: Decimal    # 0.0 to 1.0
    payment_required_wei: int    # 10% of assessed value
    payment_required_usd: Decimal
    payment_deadline: datetime   # assessment_date + 7 days
    breakdown: Dict[str, Any] = field(default_factory=dict)

    def to_contract_params(self) -> Tuple[int, int, str]:
        """Convert to parameters for NFTRights.assessValue() call."""
        return (
            self.nft_id,
            self.assessed_value_wei,
            self.methodology.value,
        )


@dataclass
class ScheduledAssessment:
    """Tracking record for a scheduled 90-day assessment."""
    nft_id: int
    mint_timestamp: datetime
    assessment_due: datetime
    status: AssessmentStatus
    valuation_result: Optional[ValuationResult] = None
    payment_deadline: Optional[datetime] = None
    payment_received: bool = False
    reverted: bool = False


# ──────────────────────────────────────────────
#  Oracle Interface (Component 11)
# ──────────────────────────────────────────────

class Component11OracleInterface:
    """
    Interface to Component 11 oracle for price feeds.
    ALL price data MUST come through this interface — NEVER call Chainlink directly.
    """

    def __init__(self, oracle_endpoint: str, api_key: Optional[str] = None):
        self._endpoint = oracle_endpoint
        self._api_key = api_key
        self._cache: Dict[str, PriceFeedData] = {}
        self._cache_ttl = 60  # 60-second cache TTL

    async def get_price(self, pair: str) -> PriceFeedData:
        """
        Fetch current price from Component 11 oracle.
        NEVER calls Chainlink directly — always through Component 11.

        Args:
            pair: Trading pair string, e.g., "ETH/USD", "MATIC/USD"

        Returns:
            PriceFeedData with current price information
        """
        cache_key = f"{pair}:{int(time.time()) // self._cache_ttl}"
        if cache_key in self._cache:
            return self._cache[cache_key]

        try:
            # Component 11 oracle call — this is the ONLY authorized price feed source
            import aiohttp
            async with aiohttp.ClientSession() as session:
                headers = {}
                if self._api_key:
                    headers["Authorization"] = f"Bearer {self._api_key}"

                async with session.get(
                    f"{self._endpoint}/v1/price-feeds/{pair}",
                    headers=headers,
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as response:
                    response.raise_for_status()
                    data = await response.json()

                    feed = PriceFeedData(
                        pair=pair,
                        price=Decimal(str(data["price"])),
                        decimals=data["decimals"],
                        updated_at=datetime.fromisoformat(data["updated_at"]),
                        round_id=data["round_id"],
                        source="component_11_oracle",
                    )

                    self._cache[cache_key] = feed
                    return feed

        except Exception as e:
            logger.error(f"Component 11 oracle price feed error for {pair}: {e}")
            raise OracleError(f"Failed to fetch price for {pair} from Component 11 oracle: {e}") from e

    async def get_eth_usd_price(self) -> Decimal:
        """Get current ETH/USD price from Component 11 oracle."""
        feed = await self.get_price("ETH/USD")
        return feed.price

    def clear_cache(self) -> None:
        """Clear the price feed cache."""
        self._cache.clear()


class OracleError(Exception):
    """Raised when Component 11 oracle is unreachable or returns an error."""
    pass


# ──────────────────────────────────────────────
#  NFT Valuation Engine
# ──────────────────────────────────────────────

class NFTValuationEngine:
    """
    Core valuation engine for OpenMatrix NFTs.

    Handles the full 90-day valuation assessment lifecycle:
      1. Scheduling assessments at mint time
      2. Computing fair market value at 90-day mark
      3. Opening the 7-day payment window
      4. Triggering rights reversion if payment is not received

    All price feeds come from Component 11 oracle — NEVER direct Chainlink calls.
    """

    def __init__(
        self,
        web3_provider: Web3,
        nft_contract: Contract,
        rights_contract: Contract,
        oracle_endpoint: str,
        oracle_api_key: Optional[str] = None,
        marketplace_subgraph_url: Optional[str] = None,
    ):
        self._w3 = web3_provider
        self._nft_contract = nft_contract
        self._rights_contract = rights_contract
        self._oracle = Component11OracleInterface(oracle_endpoint, oracle_api_key)
        self._subgraph_url = marketplace_subgraph_url

        # In-memory tracking (production would use persistent storage)
        self._scheduled_assessments: Dict[int, ScheduledAssessment] = {}

        # Lazy import of fallback engine
        self._fallback_engine: Optional[Any] = None

    @property
    def fallback_engine(self):
        """Lazy-load the ValuationFallback engine."""
        if self._fallback_engine is None:
            from runtime.blockchain.services.nft.valuation_fallback import ValuationFallback
            self._fallback_engine = ValuationFallback(
                web3_provider=self._w3,
                oracle=self._oracle,
                subgraph_url=self._subgraph_url,
            )
        return self._fallback_engine

    # ──────────────────────────────────────────
    #  Public API
    # ──────────────────────────────────────────

    async def assess_value(self, nft_id: int) -> ValuationResult:
        """
        Perform a full valuation assessment for an NFT.

        This is the primary entry point called at (or after) the 90-day mark.
        Uses secondary market trading data if available; falls back to
        comparable collection floor price or original mint value.

        Args:
            nft_id: Token ID to assess

        Returns:
            ValuationResult with assessed value, methodology, and payment info
        """
        logger.info(f"Starting valuation assessment for NFT #{nft_id}")

        # Fetch trading activity
        trading_data = await self.get_trading_activity(nft_id)

        # Get current ETH/USD price for USD conversions
        eth_usd_price = await self._oracle.get_eth_usd_price()

        if trading_data.has_secondary_trading:
            # Primary valuation: based on actual secondary market data
            result = await self._assess_from_trading_data(nft_id, trading_data, eth_usd_price)
        else:
            # Fallback valuation: comparable collection floor or mint value
            result = await self._assess_with_fallback(nft_id, trading_data, eth_usd_price)

        # Update scheduled assessment tracking
        if nft_id in self._scheduled_assessments:
            assessment = self._scheduled_assessments[nft_id]
            assessment.status = AssessmentStatus.ASSESSED
            assessment.valuation_result = result
            assessment.payment_deadline = result.payment_deadline

        logger.info(
            f"Valuation for NFT #{nft_id}: {result.assessed_value_wei} wei "
            f"(${result.assessed_value_usd}) via {result.methodology.value}, "
            f"payment required: {result.payment_required_wei} wei"
        )

        return result

    async def get_trading_activity(self, nft_id: int) -> TradingActivity:
        """
        Fetch aggregated trading activity for an NFT from on-chain data
        and marketplace subgraph.

        Args:
            nft_id: Token ID to query

        Returns:
            TradingActivity with complete sales history and statistics
        """
        sales_history: List[Dict[str, Any]] = []
        total_volume_wei = 0
        highest_sale = 0
        lowest_sale = 0
        last_sale_wei = 0
        last_sale_timestamp = None
        unique_owners_set: set = set()

        # Query marketplace subgraph for trade data
        if self._subgraph_url:
            try:
                import aiohttp
                query = """
                query GetNFTSales($tokenId: BigInt!) {
                    sales(
                        where: { tokenId: $tokenId }
                        orderBy: timestamp
                        orderDirection: desc
                    ) {
                        id
                        seller
                        buyer
                        price
                        timestamp
                        txHash
                    }
                }
                """
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        self._subgraph_url,
                        json={"query": query, "variables": {"tokenId": str(nft_id)}},
                        timeout=aiohttp.ClientTimeout(total=15),
                    ) as resp:
                        resp.raise_for_status()
                        data = await resp.json()
                        raw_sales = data.get("data", {}).get("sales", [])

                        for sale in raw_sales:
                            price_wei = int(sale["price"])
                            ts = datetime.fromtimestamp(int(sale["timestamp"]), tz=timezone.utc)
                            sales_history.append({
                                "sale_id": sale["id"],
                                "seller": sale["seller"],
                                "buyer": sale["buyer"],
                                "price_wei": price_wei,
                                "timestamp": ts,
                                "tx_hash": sale["txHash"],
                            })
                            total_volume_wei += price_wei
                            highest_sale = max(highest_sale, price_wei)
                            if lowest_sale == 0 or price_wei < lowest_sale:
                                lowest_sale = price_wei
                            unique_owners_set.add(sale["buyer"])
                            unique_owners_set.add(sale["seller"])

                        if sales_history:
                            last_sale_wei = sales_history[0]["price_wei"]
                            last_sale_timestamp = sales_history[0]["timestamp"]

            except Exception as e:
                logger.warning(f"Subgraph query failed for NFT #{nft_id}: {e}")

        # Also check on-chain NFTSold events as fallback data source
        try:
            sold_filter = self._nft_contract.events.NFTSold.create_filter(
                fromBlock=0,
                argument_filters={"tokenId": nft_id},
            )
            events = sold_filter.get_all_entries()

            for event in events:
                price_wei = event.args.salePrice
                tx_hash = event.transactionHash.hex()

                # Avoid duplicates if subgraph already captured this
                if not any(s.get("tx_hash") == tx_hash for s in sales_history):
                    block = self._w3.eth.get_block(event.blockNumber)
                    ts = datetime.fromtimestamp(block.timestamp, tz=timezone.utc)
                    sales_history.append({
                        "sale_id": f"event_{event.logIndex}",
                        "seller": event.args.seller,
                        "buyer": event.args.buyer,
                        "price_wei": price_wei,
                        "timestamp": ts,
                        "tx_hash": tx_hash,
                    })
                    total_volume_wei += price_wei
                    highest_sale = max(highest_sale, price_wei)
                    if lowest_sale == 0 or price_wei < lowest_sale:
                        lowest_sale = price_wei
                    unique_owners_set.add(event.args.buyer)
                    unique_owners_set.add(event.args.seller)

                    if last_sale_timestamp is None or ts > last_sale_timestamp:
                        last_sale_wei = price_wei
                        last_sale_timestamp = ts

        except Exception as e:
            logger.warning(f"On-chain event query failed for NFT #{nft_id}: {e}")

        total_sales = len(sales_history)
        avg_price_wei = total_volume_wei // total_sales if total_sales > 0 else 0

        # Convert to USD using Component 11 oracle
        eth_usd = await self._oracle.get_eth_usd_price()
        total_volume_usd = self._wei_to_usd(total_volume_wei, eth_usd)
        avg_price_usd = self._wei_to_usd(avg_price_wei, eth_usd)

        return TradingActivity(
            nft_id=nft_id,
            total_sales=total_sales,
            total_volume_wei=total_volume_wei,
            total_volume_usd=total_volume_usd,
            average_sale_price_wei=avg_price_wei,
            average_sale_price_usd=avg_price_usd,
            highest_sale_wei=highest_sale,
            lowest_sale_wei=lowest_sale,
            last_sale_wei=last_sale_wei,
            last_sale_timestamp=last_sale_timestamp,
            unique_owners=len(unique_owners_set),
            sales_history=sorted(sales_history, key=lambda s: s["timestamp"], reverse=True),
        )

    async def get_price_feeds(self) -> Dict[str, PriceFeedData]:
        """
        Fetch current price feeds from Component 11 oracle.
        NEVER calls Chainlink directly.

        Returns:
            Dictionary of trading pair -> PriceFeedData
        """
        pairs = ["ETH/USD", "MATIC/USD", "BASE/USD"]
        feeds: Dict[str, PriceFeedData] = {}

        for pair in pairs:
            try:
                feeds[pair] = await self._oracle.get_price(pair)
            except OracleError as e:
                logger.warning(f"Failed to fetch {pair} feed: {e}")

        return feeds

    def schedule_90_day_assessment(self, nft_id: int) -> ScheduledAssessment:
        """
        Schedule a 90-day valuation assessment for a newly minted NFT.
        Called at mint time by the platform backend.

        Args:
            nft_id: Token ID of the newly minted NFT

        Returns:
            ScheduledAssessment tracking record
        """
        now = datetime.now(timezone.utc)
        due = now + timedelta(days=VALUATION_PERIOD_DAYS)

        assessment = ScheduledAssessment(
            nft_id=nft_id,
            mint_timestamp=now,
            assessment_due=due,
            status=AssessmentStatus.SCHEDULED,
        )

        self._scheduled_assessments[nft_id] = assessment

        logger.info(
            f"Scheduled 90-day assessment for NFT #{nft_id}: "
            f"due {due.isoformat()}"
        )

        return assessment

    async def trigger_payment_window(self, nft_id: int) -> ValuationResult:
        """
        Trigger the 7-day payment window after valuation assessment.

        If the assessment has not been performed yet, it will be computed first.
        Submits the assessed value to the NFTRights smart contract which opens
        the on-chain payment window.

        Args:
            nft_id: Token ID

        Returns:
            ValuationResult that was submitted to the contract
        """
        # Ensure assessment exists
        if nft_id not in self._scheduled_assessments:
            raise ValueError(f"No scheduled assessment for NFT #{nft_id}")

        assessment = self._scheduled_assessments[nft_id]

        # Perform valuation if not already done
        if assessment.valuation_result is None:
            assessment.valuation_result = await self.assess_value(nft_id)

        result = assessment.valuation_result

        # Submit to NFTRights contract on-chain
        try:
            tx = self._rights_contract.functions.assessValue(
                result.nft_id,
                result.assessed_value_wei,
                result.methodology.value,
            ).build_transaction({
                "from": self._w3.eth.default_account,
                "nonce": self._w3.eth.get_transaction_count(self._w3.eth.default_account),
                "gas": 300000,
            })

            signed = self._w3.eth.account.sign_transaction(tx)
            tx_hash = self._w3.eth.send_raw_transaction(signed.rawTransaction)
            receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

            if receipt.status != 1:
                raise RuntimeError(f"assessValue transaction reverted: {tx_hash.hex()}")

            assessment.status = AssessmentStatus.PAYMENT_WINDOW_OPEN
            assessment.payment_deadline = result.payment_deadline

            logger.info(
                f"Payment window opened for NFT #{nft_id}: "
                f"required={result.payment_required_wei} wei, "
                f"deadline={result.payment_deadline.isoformat()}, "
                f"tx={tx_hash.hex()}"
            )

        except Exception as e:
            logger.error(f"Failed to submit assessment to NFTRights for NFT #{nft_id}: {e}")
            raise

        return result

    # ──────────────────────────────────────────
    #  Automation: Check Due Assessments
    # ──────────────────────────────────────────

    async def check_and_process_due_assessments(self) -> List[ValuationResult]:
        """
        Check all scheduled assessments and process any that are due.
        Designed to be called periodically by a scheduler/cron job.

        Returns:
            List of ValuationResults for assessments that were processed
        """
        now = datetime.now(timezone.utc)
        results: List[ValuationResult] = []

        for nft_id, assessment in list(self._scheduled_assessments.items()):
            if assessment.status == AssessmentStatus.SCHEDULED and now >= assessment.assessment_due:
                try:
                    result = await self.trigger_payment_window(nft_id)
                    results.append(result)
                except Exception as e:
                    logger.error(f"Failed to process due assessment for NFT #{nft_id}: {e}")

        return results

    async def check_expired_payment_windows(self) -> List[int]:
        """
        Check for expired payment windows and trigger rights reversion.

        Returns:
            List of NFT IDs that had their rights reverted
        """
        now = datetime.now(timezone.utc)
        reverted: List[int] = []

        for nft_id, assessment in list(self._scheduled_assessments.items()):
            if (
                assessment.status == AssessmentStatus.PAYMENT_WINDOW_OPEN
                and assessment.payment_deadline
                and now > assessment.payment_deadline
                and not assessment.payment_received
            ):
                try:
                    tx = self._rights_contract.functions.executeRightsReversion(
                        nft_id
                    ).build_transaction({
                        "from": self._w3.eth.default_account,
                        "nonce": self._w3.eth.get_transaction_count(self._w3.eth.default_account),
                        "gas": 200000,
                    })

                    signed = self._w3.eth.account.sign_transaction(tx)
                    tx_hash = self._w3.eth.send_raw_transaction(signed.rawTransaction)
                    receipt = self._w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

                    if receipt.status == 1:
                        assessment.status = AssessmentStatus.RIGHTS_REVERTED
                        assessment.reverted = True
                        reverted.append(nft_id)
                        logger.info(f"Rights reverted for NFT #{nft_id}: tx={tx_hash.hex()}")
                    else:
                        logger.error(f"Rights reversion tx reverted for NFT #{nft_id}")

                except Exception as e:
                    logger.error(f"Failed to execute rights reversion for NFT #{nft_id}: {e}")

        return reverted

    # ──────────────────────────────────────────
    #  Internal Valuation Methods
    # ──────────────────────────────────────────

    async def _assess_from_trading_data(
        self,
        nft_id: int,
        trading_data: TradingActivity,
        eth_usd_price: Decimal,
    ) -> ValuationResult:
        """
        Assess value based on actual secondary market trading data.
        Uses volume-weighted average with recency bias.
        """
        now = datetime.now(timezone.utc)

        # Volume-weighted average price with recency weighting
        if not trading_data.sales_history:
            raise ValueError(f"No trading data available for NFT #{nft_id}")

        total_weight = Decimal("0")
        weighted_sum = Decimal("0")

        for sale in trading_data.sales_history:
            # More recent sales get higher weight
            age_days = (now - sale["timestamp"]).days
            recency_weight = Decimal("1") / (Decimal("1") + Decimal(str(age_days)) / Decimal("30"))

            # Volume weight (higher-value trades count more)
            price_d = Decimal(str(sale["price_wei"]))
            weight = recency_weight * price_d

            weighted_sum += price_d * weight
            total_weight += weight

        assessed_value_wei = int(weighted_sum / total_weight) if total_weight > 0 else trading_data.average_sale_price_wei

        # Confidence based on number of sales and recency
        confidence = min(
            Decimal("1.0"),
            Decimal(str(trading_data.total_sales)) / Decimal("10")
            * (Decimal("1") if trading_data.last_sale_timestamp and (now - trading_data.last_sale_timestamp).days < 30 else Decimal("0.5"))
        )

        assessed_value_usd = self._wei_to_usd(assessed_value_wei, eth_usd_price)
        payment_required_wei = int(Decimal(str(assessed_value_wei)) * PAYMENT_PERCENTAGE)
        payment_required_usd = self._wei_to_usd(payment_required_wei, eth_usd_price)

        return ValuationResult(
            nft_id=nft_id,
            assessed_value_wei=assessed_value_wei,
            assessed_value_usd=assessed_value_usd,
            methodology=ValuationMethodology.SECONDARY_MARKET,
            trading_data=trading_data,
            assessment_date=now,
            confidence_score=confidence,
            payment_required_wei=payment_required_wei,
            payment_required_usd=payment_required_usd,
            payment_deadline=now + timedelta(days=PAYMENT_WINDOW_DAYS),
            breakdown={
                "method": "volume_weighted_recency_average",
                "total_sales": trading_data.total_sales,
                "total_volume_wei": trading_data.total_volume_wei,
                "highest_sale_wei": trading_data.highest_sale_wei,
                "last_sale_wei": trading_data.last_sale_wei,
                "eth_usd_price": str(eth_usd_price),
            },
        )

    async def _assess_with_fallback(
        self,
        nft_id: int,
        trading_data: TradingActivity,
        eth_usd_price: Decimal,
    ) -> ValuationResult:
        """
        Fallback valuation when no secondary trading exists.
        Delegates to ValuationFallback engine.
        """
        now = datetime.now(timezone.utc)

        # Try comparable collection floor price first, then mint value
        fallback_value_wei = await self.fallback_engine.fallback_valuation(nft_id)

        # Determine which fallback method was used
        methodology = ValuationMethodology.MINT_VALUE_FALLBACK
        breakdown: Dict[str, Any] = {"method": "fallback"}

        # Check if a comparable collection was found
        try:
            token_info = self._nft_contract.functions.tokenInfo(nft_id).call()
            metadata_uri = token_info[5]  # metadataURI field

            comparable = await self.fallback_engine.find_comparable_collection({"uri": metadata_uri, "nft_id": nft_id})
            if comparable and comparable.verified:
                floor_price = await self.fallback_engine.get_floor_price(comparable.address)
                if floor_price > 0:
                    methodology = ValuationMethodology.COMPARABLE_COLLECTION
                    breakdown["comparable_collection"] = comparable.name
                    breakdown["comparable_address"] = comparable.address
                    breakdown["floor_price_wei"] = str(floor_price)
        except Exception as e:
            logger.warning(f"Comparable collection lookup failed for NFT #{nft_id}: {e}")

        assessed_value_usd = self._wei_to_usd(int(fallback_value_wei), eth_usd_price)
        payment_required_wei = int(fallback_value_wei * PAYMENT_PERCENTAGE)
        payment_required_usd = self._wei_to_usd(payment_required_wei, eth_usd_price)

        return ValuationResult(
            nft_id=nft_id,
            assessed_value_wei=int(fallback_value_wei),
            assessed_value_usd=assessed_value_usd,
            methodology=methodology,
            trading_data=trading_data,
            assessment_date=now,
            confidence_score=Decimal("0.3") if methodology == ValuationMethodology.MINT_VALUE_FALLBACK else Decimal("0.6"),
            payment_required_wei=payment_required_wei,
            payment_required_usd=payment_required_usd,
            payment_deadline=now + timedelta(days=PAYMENT_WINDOW_DAYS),
            breakdown=breakdown,
        )

    # ──────────────────────────────────────────
    #  Helpers
    # ──────────────────────────────────────────

    @staticmethod
    def _wei_to_usd(wei_amount: int, eth_usd_price: Decimal) -> Decimal:
        """Convert wei to USD using the given ETH/USD price."""
        eth_amount = Decimal(str(wei_amount)) / Decimal("1000000000000000000")  # 1e18
        return (eth_amount * eth_usd_price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    def get_assessment_status(self, nft_id: int) -> Optional[ScheduledAssessment]:
        """Get the current assessment status for an NFT."""
        return self._scheduled_assessments.get(nft_id)
