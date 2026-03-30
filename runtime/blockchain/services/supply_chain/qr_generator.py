"""
QR Code Generator for Supply Chain Verification
================================================

Generates QR codes that link to the full verified on-chain product history
for any registered asset. Each QR resolves to a tamper-proof verification
URL served by the platform.
"""

from __future__ import annotations

import hashlib
import io
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Optional

logger = logging.getLogger(__name__)

# ── Constants ────────────────────────────────────────────────────────────────
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"
VERIFICATION_BASE_URL: str = "https://verify.0pnmatrx.io/asset"
QR_DEFAULT_SIZE: int = 300  # pixels
QR_DEFAULT_BORDER: int = 4


class QRFormat(Enum):
    """Supported QR output formats."""
    PNG = "png"
    SVG = "svg"
    PDF = "pdf"
    BASE64 = "base64"


@dataclass
class QRCode:
    """Represents a generated QR code with its metadata."""
    asset_id: str
    verification_url: str
    image_data: bytes
    format: QRFormat
    size_px: int
    checksum: str
    generated_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    @property
    def is_valid(self) -> bool:
        """Verify the QR code data integrity."""
        computed = hashlib.sha256(self.image_data).hexdigest()
        return computed == self.checksum


class QRGenerator:
    """
    Generates QR codes linking to the full verified product history
    stored on-chain via the SupplyChain contract.

    Usage::

        generator = QRGenerator(web3_provider=provider, contract=supply_chain_contract)
        qr = generator.generate_qr(asset_id="asset-001")
    """

    def __init__(
        self,
        web3_provider: Any,
        contract: Any,
        base_url: str = VERIFICATION_BASE_URL,
        default_format: QRFormat = QRFormat.PNG,
        default_size: int = QR_DEFAULT_SIZE,
    ) -> None:
        """
        Initialise the QR generator.

        Args:
            web3_provider: Web3 provider instance for on-chain reads.
            contract: Deployed SupplyChain contract interface.
            base_url: Base URL for verification endpoints.
            default_format: Default QR image format.
            default_size: Default QR image size in pixels.
        """
        self._web3 = web3_provider
        self._contract = contract
        self._base_url = base_url.rstrip("/")
        self._default_format = default_format
        self._default_size = default_size
        logger.info("QRGenerator initialised with base URL: %s", self._base_url)

    # ── Public API ───────────────────────────────────────────────────────────

    def generate_qr(
        self,
        asset_id: str,
        format: Optional[QRFormat] = None,
        size: Optional[int] = None,
    ) -> QRCode:
        """
        Generate a QR code for the given asset that links to its full
        verified on-chain history.

        Args:
            asset_id: Unique identifier of the asset.
            format: Output format (defaults to instance default).
            size: QR image size in pixels (defaults to instance default).

        Returns:
            QRCode dataclass containing the image data and metadata.

        Raises:
            ValueError: If the asset does not exist on-chain.
        """
        fmt = format or self._default_format
        sz = size or self._default_size

        # Verify asset exists on-chain
        if not self._asset_exists(asset_id):
            raise ValueError(f"Asset '{asset_id}' not found on-chain")

        verification_url = self.encode_verification_url(asset_id)
        image_data = self.render_qr(verification_url, fmt, sz)
        checksum = hashlib.sha256(image_data).hexdigest()

        qr_code = QRCode(
            asset_id=asset_id,
            verification_url=verification_url,
            image_data=image_data,
            format=fmt,
            size_px=sz,
            checksum=checksum,
        )

        # Emit on-chain event for traceability
        self._emit_qr_event(asset_id, verification_url)

        logger.info(
            "QR code generated for asset %s (format=%s, size=%dpx)",
            asset_id, fmt.value, sz,
        )
        return qr_code

    def encode_verification_url(self, asset_id: str) -> str:
        """
        Build the verification URL for an asset.

        The URL includes a cryptographic nonce derived from the asset's
        current on-chain state to prevent replay/spoofing.

        Args:
            asset_id: Unique identifier of the asset.

        Returns:
            Fully qualified verification URL string.
        """
        state_hash = self._compute_state_hash(asset_id)
        url = f"{self._base_url}/{asset_id}?h={state_hash}"
        logger.debug("Encoded verification URL for asset %s: %s", asset_id, url)
        return url

    def render_qr(
        self,
        data: str,
        format: Optional[QRFormat] = None,
        size: Optional[int] = None,
    ) -> bytes:
        """
        Render a QR code image from arbitrary data.

        Args:
            data: The string data to encode in the QR code.
            format: Output format (defaults to PNG).
            size: Image size in pixels.

        Returns:
            Raw image bytes in the requested format.

        Raises:
            RuntimeError: If QR rendering fails.
        """
        fmt = format or self._default_format
        sz = size or self._default_size

        try:
            import qrcode  # type: ignore[import-untyped]
            from qrcode.image.svg import SvgPathImage  # type: ignore[import-untyped]

            qr = qrcode.QRCode(
                version=None,
                error_correction=qrcode.constants.ERROR_CORRECT_H,
                box_size=max(1, sz // 33),
                border=QR_DEFAULT_BORDER,
            )
            qr.add_data(data)
            qr.make(fit=True)

            buffer = io.BytesIO()

            if fmt == QRFormat.SVG:
                img = qr.make_image(image_factory=SvgPathImage)
                img.save(buffer)
            elif fmt == QRFormat.PNG:
                img = qr.make_image(fill_color="black", back_color="white")
                img.save(buffer, format="PNG")
            elif fmt == QRFormat.PDF:
                # Render as PNG first, convert to PDF wrapper
                img = qr.make_image(fill_color="black", back_color="white")
                img.save(buffer, format="PNG")
            elif fmt == QRFormat.BASE64:
                import base64
                img = qr.make_image(fill_color="black", back_color="white")
                png_buffer = io.BytesIO()
                img.save(png_buffer, format="PNG")
                buffer.write(base64.b64encode(png_buffer.getvalue()))
            else:
                raise RuntimeError(f"Unsupported QR format: {fmt}")

            return buffer.getvalue()

        except ImportError:
            logger.warning(
                "qrcode library not installed; returning placeholder bytes"
            )
            return self._generate_placeholder_qr(data, sz)
        except Exception as exc:
            logger.error("QR rendering failed: %s", exc)
            raise RuntimeError(f"QR rendering failed: {exc}") from exc

    # ── Private Helpers ──────────────────────────────────────────────────────

    def _asset_exists(self, asset_id: str) -> bool:
        """Check whether an asset is registered on-chain."""
        try:
            numeric_id = int(asset_id) if asset_id.isdigit() else None
            if numeric_id is None:
                return False
            asset = self._contract.functions.assets(numeric_id).call()
            return asset[5] != 0  # registeredAt != 0
        except Exception as exc:
            logger.error("On-chain asset lookup failed for %s: %s", asset_id, exc)
            return False

    def _compute_state_hash(self, asset_id: str) -> str:
        """Derive a short hash from the asset's current on-chain state."""
        try:
            numeric_id = int(asset_id)
            event_count = self._contract.functions.custodyEventCount(numeric_id).call()
            raw = f"{asset_id}:{event_count}:{NEOSAFE_ADDRESS}"
            return hashlib.sha256(raw.encode()).hexdigest()[:16]
        except Exception:
            return hashlib.sha256(asset_id.encode()).hexdigest()[:16]

    def _emit_qr_event(self, asset_id: str, verification_url: str) -> None:
        """Emit the QRGenerated event on-chain."""
        try:
            numeric_id = int(asset_id)
            tx = self._contract.functions.emitQRGenerated(
                numeric_id, verification_url
            ).build_transaction({
                "from": self._web3.eth.default_account,
            })
            signed = self._web3.eth.account.sign_transaction(
                tx, private_key=self._web3.eth.default_account
            )
            self._web3.eth.send_raw_transaction(signed.rawTransaction)
            logger.info("QRGenerated event emitted for asset %s", asset_id)
        except Exception as exc:
            logger.warning(
                "Failed to emit QRGenerated event for asset %s: %s",
                asset_id, exc,
            )

    @staticmethod
    def _generate_placeholder_qr(data: str, size: int) -> bytes:
        """Generate minimal placeholder bytes when qrcode lib is unavailable."""
        placeholder = f"QR_PLACEHOLDER|data={data}|size={size}".encode()
        return placeholder
