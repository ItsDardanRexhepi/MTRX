"""Check cryptocurrency prices — a sample Matrix skill."""

SKILL_NAME = "price_check"
SKILL_DESCRIPTION = "Check current cryptocurrency prices"
SKILL_VERSION = "1.0"
SKILL_AGENT = "all"
SKILL_TAGS = ["crypto", "price", "market"]


async def execute(context: dict) -> dict:
    """
    Check crypto prices. Context should include:
    - symbol: The token symbol (e.g., "ETH", "BTC")
    """
    import httpx

    symbol = context.get("symbol", "ETH").upper()
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                f"https://api.coingecko.com/api/v3/simple/price",
                params={"ids": _symbol_to_id(symbol), "vs_currencies": "usd"},
            )
            data = resp.json()
            coin_id = _symbol_to_id(symbol)
            price = data.get(coin_id, {}).get("usd")
            if price is not None:
                return {"symbol": symbol, "price_usd": price, "source": "coingecko"}
            return {"error": f"Price not found for {symbol}"}
    except Exception as e:
        return {"error": str(e)}


def _symbol_to_id(symbol: str) -> str:
    mapping = {
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana",
        "MATIC": "matic-network", "AVAX": "avalanche-2",
        "DOT": "polkadot", "LINK": "chainlink", "UNI": "uniswap",
        "AAVE": "aave", "ARB": "arbitrum", "OP": "optimism",
    }
    return mapping.get(symbol, symbol.lower())
