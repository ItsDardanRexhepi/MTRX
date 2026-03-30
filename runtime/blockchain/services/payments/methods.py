"""
Payment Method Registry — extensible registry for adding new payment methods.

Part of Component 17 (Payments).
Supports native crypto, stablecoins, and future method types via plugin architecture.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional, Protocol

logger = logging.getLogger(__name__)


class MethodCategory(Enum):
    """Categories of payment methods."""
    NATIVE_CRYPTO = "native_crypto"
    STABLECOIN = "stablecoin"
    WRAPPED_TOKEN = "wrapped_token"
    BRIDGE = "bridge"
    CUSTOM = "custom"


class PaymentMethodHandler(Protocol):
    """Protocol that all payment method handlers must implement."""

    def execute(self, sender: str, recipient: str, amount_wei: int) -> Optional[str]:
        """Execute a payment. Returns transaction hash or None."""
        ...

    def validate(self, sender: str, amount_wei: int) -> bool:
        """Validate that the sender can make this payment."""
        ...

    def get_estimated_time(self) -> int:
        """Return estimated processing time in seconds."""
        ...


@dataclass
class PaymentMethod:
    """A registered payment method."""
    method_id: str
    name: str
    category: MethodCategory
    description: str
    handler: Optional[Any] = None
    is_active: bool = True
    supported_currencies: List[str] = field(default_factory=list)
    min_amount_wei: int = 0
    max_amount_wei: int = 0   # 0 = no limit
    registered_at: float = field(default_factory=time.time)
    metadata: Dict[str, Any] = field(default_factory=dict)


class PaymentMethodRegistry:
    """
    Extensible registry for payment methods.

    New payment methods can be registered at runtime via the plugin
    architecture. Each method must provide a handler implementing
    the PaymentMethodHandler protocol.

    Built-in methods:
    - native: Direct ETH transfer
    - usdc: USDC stablecoin transfer
    - usdt: USDT stablecoin transfer
    - dai: DAI stablecoin transfer
    """

    def __init__(self) -> None:
        self._methods: Dict[str, PaymentMethod] = {}
        self._default_method: str = "native"

        # Register built-in methods
        self._register_builtins()
        logger.info(
            "PaymentMethodRegistry initialised with %d built-in methods.",
            len(self._methods),
        )

    # ── Registration ──────────────────────────────────────────────────

    def register_method(
        self,
        method_id: str,
        name: str,
        category: MethodCategory,
        description: str,
        handler: Optional[Any] = None,
        supported_currencies: Optional[List[str]] = None,
        min_amount_wei: int = 0,
        max_amount_wei: int = 0,
    ) -> PaymentMethod:
        """
        Register a new payment method.

        Args:
            method_id: Unique identifier for the method.
            name: Human-readable name.
            category: Method category.
            description: Description of the method.
            handler: Object implementing PaymentMethodHandler protocol.
            supported_currencies: List of supported currency codes.
            min_amount_wei: Minimum payment amount.
            max_amount_wei: Maximum payment amount (0 = no limit).

        Returns:
            The registered PaymentMethod.

        Raises:
            ValueError: If method_id already exists.
        """
        if method_id in self._methods:
            raise ValueError(f"Payment method '{method_id}' is already registered.")

        method = PaymentMethod(
            method_id=method_id,
            name=name,
            category=category,
            description=description,
            handler=handler,
            supported_currencies=supported_currencies or [],
            min_amount_wei=min_amount_wei,
            max_amount_wei=max_amount_wei,
        )
        self._methods[method_id] = method

        logger.info(
            "Payment method registered | id=%s | name=%s | category=%s",
            method_id, name, category.value,
        )
        return method

    def unregister_method(self, method_id: str) -> None:
        """
        Deactivate a payment method (soft delete).

        Args:
            method_id: The method to deactivate.

        Raises:
            ValueError: If method not found or is the default.
        """
        if method_id == self._default_method:
            raise ValueError("Cannot unregister the default payment method.")
        method = self._get_method(method_id)
        method.is_active = False
        logger.info("Payment method deactivated: %s", method_id)

    # ── Resolution ────────────────────────────────────────────────────

    def get_method(self, method_id: str) -> Optional[PaymentMethod]:
        """Get a payment method by ID."""
        method = self._methods.get(method_id)
        if method and method.is_active:
            return method
        return None

    def resolve_method(
        self,
        method_id: Optional[str] = None,
        currency: Optional[str] = None,
        amount_wei: int = 0,
    ) -> PaymentMethod:
        """
        Resolve the best payment method for given parameters.

        Args:
            method_id: Explicit method ID (if user selected one).
            currency: Desired currency.
            amount_wei: Payment amount.

        Returns:
            The resolved PaymentMethod.

        Raises:
            ValueError: If no suitable method is found.
        """
        if method_id is not None:
            method = self.get_method(method_id)
            if method is None:
                raise ValueError(f"Payment method '{method_id}' not found or inactive.")
            self._validate_method_for_amount(method, amount_wei)
            return method

        # Auto-resolve by currency
        if currency is not None:
            currency = currency.upper()
            for method in self._methods.values():
                if (
                    method.is_active
                    and currency in method.supported_currencies
                    and self._amount_in_range(method, amount_wei)
                ):
                    return method

        # Fallback to default
        default = self._methods.get(self._default_method)
        if default is None or not default.is_active:
            raise ValueError("No default payment method available.")
        return default

    def list_methods(self, active_only: bool = True) -> List[PaymentMethod]:
        """
        List all registered payment methods.

        Args:
            active_only: If True, only return active methods.

        Returns:
            List of PaymentMethod objects.
        """
        methods = list(self._methods.values())
        if active_only:
            methods = [m for m in methods if m.is_active]
        return methods

    def list_methods_for_currency(self, currency: str) -> List[PaymentMethod]:
        """List all active methods supporting a specific currency."""
        currency = currency.upper()
        return [
            m for m in self._methods.values()
            if m.is_active and currency in m.supported_currencies
        ]

    def set_default_method(self, method_id: str) -> None:
        """Set the default payment method."""
        method = self._get_method(method_id)
        if not method.is_active:
            raise ValueError(f"Cannot set inactive method '{method_id}' as default.")
        self._default_method = method_id
        logger.info("Default payment method set to: %s", method_id)

    # ── Internal ──────────────────────────────────────────────────────

    def _register_builtins(self) -> None:
        """Register built-in payment methods."""
        builtins = [
            ("native", "Native ETH", MethodCategory.NATIVE_CRYPTO,
             "Direct ETH transfer on Base network.", ["ETH", "WETH"]),
            ("usdc", "USDC", MethodCategory.STABLECOIN,
             "Circle USDC stablecoin payment.", ["USDC"]),
            ("usdt", "USDT", MethodCategory.STABLECOIN,
             "Tether USDT stablecoin payment.", ["USDT"]),
            ("dai", "DAI", MethodCategory.STABLECOIN,
             "MakerDAO DAI stablecoin payment.", ["DAI"]),
        ]
        for method_id, name, category, description, currencies in builtins:
            self._methods[method_id] = PaymentMethod(
                method_id=method_id,
                name=name,
                category=category,
                description=description,
                supported_currencies=currencies,
            )

    def _get_method(self, method_id: str) -> PaymentMethod:
        """Get a method or raise."""
        method = self._methods.get(method_id)
        if method is None:
            raise ValueError(f"Payment method '{method_id}' not found.")
        return method

    def _validate_method_for_amount(self, method: PaymentMethod, amount_wei: int) -> None:
        """Validate amount is within method's range."""
        if not self._amount_in_range(method, amount_wei):
            raise ValueError(
                f"Amount {amount_wei} is outside the range for method '{method.method_id}' "
                f"(min={method.min_amount_wei}, max={method.max_amount_wei})."
            )

    def _amount_in_range(self, method: PaymentMethod, amount_wei: int) -> bool:
        """Check if amount is within method's allowed range."""
        if amount_wei < method.min_amount_wei:
            return False
        if method.max_amount_wei > 0 and amount_wei > method.max_amount_wei:
            return False
        return True
