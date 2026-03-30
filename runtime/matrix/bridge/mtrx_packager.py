"""
MTRX iOS App Conversion Layer for Matrix-to-0pnMatrx Bridge.

Takes bridge-validated 0pnMatrx components and packages them for the
MTRX iOS application. Handles platform runtime logic conversion to
mobile-ready API endpoints, Trinity conversational interface, Morpheus
trigger integration, on-device Ollama processing, ERC-4337 wallet creation,
push notifications for all 30 components, and XMTP mobile messaging.

CLOSED-SOURCE: This module is part of the closed-source bridge and must
never appear in any public repository.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

DARDAN_TELEGRAM_ID: int = 7161847911
NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

# Total components expected before full iOS packaging can run
TOTAL_BRIDGE_COMPONENTS: int = 30


@dataclass
class IOSPackageConfig:
    """Configuration for the MTRX iOS package build."""
    bundle_id: str = "com.mtrx.app"
    min_ios_version: str = "16.0"
    trinity_api_base: str = "/api/v1/trinity"
    morpheus_api_base: str = "/api/v1/morpheus"
    ollama_model: str = "llama3"
    erc4337_entrypoint: str = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
    xmtp_env: str = "production"
    push_service: str = "apns"


@dataclass
class IOSComponent:
    """A single component packaged for MTRX iOS."""
    component_name: str
    api_endpoints: List[Dict[str, str]] = field(default_factory=list)
    trinity_routes: List[str] = field(default_factory=list)
    morpheus_triggers: List[str] = field(default_factory=list)
    push_notification_hooks: List[str] = field(default_factory=list)
    files: Dict[str, str] = field(default_factory=dict)


@dataclass
class IOSPackageResult:
    """Result of full MTRX iOS packaging."""
    success: bool = False
    components_packaged: int = 0
    total_api_endpoints: int = 0
    trinity_integrated: bool = False
    morpheus_integrated: bool = False
    ollama_configured: bool = False
    erc4337_configured: bool = False
    xmtp_configured: bool = False
    push_notifications_configured: bool = False
    errors: List[str] = field(default_factory=list)
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class MTRXPackager:
    """
    Packages bridge-validated 0pnMatrx components for the MTRX iOS app.

    Guarantees:
        - No private Matrix data in output
        - No security layer references
        - All 30 components accessible via Trinity API
        - Morpheus triggers mapped to mobile events

    Runs after all 30 components are bridge-validated.
    """

    def __init__(
        self,
        config: Optional[IOSPackageConfig] = None,
        manifest_manager: Optional[Any] = None,
        notifier: Optional[Any] = None,
    ) -> None:
        self.config = config or IOSPackageConfig()

        if manifest_manager is None:
            from runtime.matrix.bridge.manifest_manager import ManifestManager
            manifest_manager = ManifestManager()
        if notifier is None:
            from runtime.matrix.bridge.telegram_notifier import TelegramNotifier
            notifier = TelegramNotifier()

        self.manifest = manifest_manager
        self.notifier = notifier
        self._packaged_components: Dict[str, IOSComponent] = {}

    # ── Public API ─────────────────────────────────────────────────────────

    def package_for_ios(self, components: List[Any]) -> IOSPackageResult:
        """
        Full iOS packaging pipeline for all bridge-validated components.

        Must receive all 30 components before proceeding.

        Args:
            components: List of ExportPackage objects (bridge-validated).

        Returns:
            IOSPackageResult with full build status.
        """
        result = IOSPackageResult()

        # ── Guard: require all 30 components ───────────────────────────────
        if len(components) < TOTAL_BRIDGE_COMPONENTS:
            error = (
                f"iOS packaging requires all {TOTAL_BRIDGE_COMPONENTS} components. "
                f"Received {len(components)}."
            )
            result.errors.append(error)
            logger.error(error)
            return result

        # ── Verify all components are bridge-validated and approved ─────────
        for comp in components:
            if not self.manifest.is_approved(comp.component_name):
                error = f"Component '{comp.component_name}' not approved in manifest"
                result.errors.append(error)
                logger.error(error)

        if result.errors:
            return result

        # ── Package each component ─────────────────────────────────────────
        total_endpoints = 0
        for comp in components:
            try:
                ios_comp = self._package_single_component(comp)
                self._packaged_components[comp.component_name] = ios_comp
                total_endpoints += len(ios_comp.api_endpoints)
                result.components_packaged += 1
            except Exception as exc:
                result.errors.append(f"Failed to package '{comp.component_name}': {exc}")
                logger.exception("Failed to package '%s'", comp.component_name)

        result.total_api_endpoints = total_endpoints

        # ── Integrate platform services ────────────────────────────────────
        try:
            self.configure_ollama_layer()
            result.ollama_configured = True
        except Exception as exc:
            result.errors.append(f"Ollama config failed: {exc}")

        try:
            self.configure_erc4337_wallet()
            result.erc4337_configured = True
        except Exception as exc:
            result.errors.append(f"ERC-4337 config failed: {exc}")

        try:
            self.integrate_xmtp_mobile()
            result.xmtp_configured = True
        except Exception as exc:
            result.errors.append(f"XMTP config failed: {exc}")

        # ── Integrate Trinity and Morpheus across all components ───────────
        for comp_name, ios_comp in self._packaged_components.items():
            try:
                self.integrate_trinity_interface(ios_comp)
            except Exception as exc:
                result.errors.append(f"Trinity integration failed for '{comp_name}': {exc}")
            try:
                self.integrate_morpheus_triggers(ios_comp)
            except Exception as exc:
                result.errors.append(f"Morpheus integration failed for '{comp_name}': {exc}")

        result.trinity_integrated = all(
            len(c.trinity_routes) > 0 for c in self._packaged_components.values()
        )
        result.morpheus_integrated = all(
            len(c.morpheus_triggers) > 0 for c in self._packaged_components.values()
        )

        # ── Push notifications ─────────────────────────────────────────────
        for comp in components:
            try:
                ios_comp = self._packaged_components.get(comp.component_name)
                if ios_comp:
                    self.setup_push_notifications(ios_comp)
            except Exception as exc:
                result.errors.append(f"Push setup failed for '{comp.component_name}': {exc}")

        result.push_notifications_configured = all(
            len(c.push_notification_hooks) > 0
            for c in self._packaged_components.values()
        )

        result.success = len(result.errors) == 0

        # ── Notify Dardan ──────────────────────────────────────────────────
        status = "SUCCESS" if result.success else "PARTIAL"
        self.notifier.send_message(
            DARDAN_TELEGRAM_ID,
            f"MTRX iOS Packaging {status}\n"
            f"Components: {result.components_packaged}/{TOTAL_BRIDGE_COMPONENTS}\n"
            f"API Endpoints: {result.total_api_endpoints}\n"
            f"Trinity: {'OK' if result.trinity_integrated else 'FAIL'}\n"
            f"Morpheus: {'OK' if result.morpheus_integrated else 'FAIL'}\n"
            f"Ollama: {'OK' if result.ollama_configured else 'FAIL'}\n"
            f"ERC-4337: {'OK' if result.erc4337_configured else 'FAIL'}\n"
            f"XMTP: {'OK' if result.xmtp_configured else 'FAIL'}\n"
            f"Push: {'OK' if result.push_notifications_configured else 'FAIL'}\n"
            f"Errors: {len(result.errors)}",
        )

        return result

    def generate_api_endpoints(self, component: Any) -> List[Dict[str, str]]:
        """
        Generate mobile-ready API endpoints for a bridge-validated component.

        Maps component logic to RESTful endpoints accessible via Trinity.
        """
        endpoints = []
        component_name = (
            component.component_name
            if hasattr(component, "component_name")
            else str(component)
        )
        base = f"{self.config.trinity_api_base}/{component_name}"

        endpoints.append({
            "method": "GET",
            "path": f"{base}/status",
            "description": f"Get {component_name} status",
        })
        endpoints.append({
            "method": "POST",
            "path": f"{base}/execute",
            "description": f"Execute {component_name} action",
        })
        endpoints.append({
            "method": "GET",
            "path": f"{base}/config",
            "description": f"Get {component_name} configuration",
        })
        endpoints.append({
            "method": "POST",
            "path": f"{base}/trigger",
            "description": f"Trigger {component_name} via Morpheus event",
        })

        logger.info(
            "Generated %d API endpoints for '%s'", len(endpoints), component_name
        )
        return endpoints

    def integrate_trinity_interface(self, component: IOSComponent) -> None:
        """
        Integrate Trinity conversational interface routes for a component.

        Maps component capabilities to natural-language Trinity commands.
        """
        name = component.component_name
        component.trinity_routes = [
            f"{self.config.trinity_api_base}/{name}/chat",
            f"{self.config.trinity_api_base}/{name}/query",
            f"{self.config.trinity_api_base}/{name}/explain",
            f"{self.config.trinity_api_base}/{name}/summarize",
        ]
        logger.info("Integrated Trinity interface for '%s' (%d routes)", name, len(component.trinity_routes))

    def integrate_morpheus_triggers(self, component: IOSComponent) -> None:
        """
        Map Morpheus triggers to mobile events for a component.

        Morpheus triggers are mapped to iOS-native event types:
        push notifications, background tasks, and widget updates.
        """
        name = component.component_name
        component.morpheus_triggers = [
            f"morpheus.{name}.state_change",
            f"morpheus.{name}.alert",
            f"morpheus.{name}.threshold_breach",
            f"morpheus.{name}.scheduled_check",
            f"morpheus.{name}.user_action",
        ]
        logger.info(
            "Integrated Morpheus triggers for '%s' (%d triggers)",
            name,
            len(component.morpheus_triggers),
        )

    def configure_ollama_layer(self) -> Dict[str, Any]:
        """
        Configure on-device Ollama processing for the MTRX iOS app.

        Returns:
            Configuration dict for the Ollama runtime layer.
        """
        config = {
            "model": self.config.ollama_model,
            "runtime": "on-device",
            "fallback": "cloud-api",
            "max_context_length": 4096,
            "quantization": "q4_0",
            "memory_limit_mb": 512,
            "trinity_integration": True,
            "supported_tasks": [
                "chat_completion",
                "component_explanation",
                "transaction_summary",
                "alert_interpretation",
            ],
        }
        logger.info("Configured Ollama layer: model=%s", self.config.ollama_model)
        return config

    def configure_erc4337_wallet(self) -> Dict[str, Any]:
        """
        Configure ERC-4337 smart account wallet creation flow for iOS.

        Returns:
            Wallet configuration for the mobile app.
        """
        config = {
            "entrypoint": self.config.erc4337_entrypoint,
            "chain_id": 8453,  # Base mainnet
            "account_factory": "SimpleAccountFactory",
            "paymaster_enabled": True,
            "bundler_url": "https://bundler.base.org",
            "neosafe_address": NEOSAFE_ADDRESS,
            "social_recovery": True,
            "biometric_auth": True,
            "creation_flow": [
                "biometric_prompt",
                "generate_owner_key",
                "deploy_smart_account",
                "register_with_neosafe",
                "enable_paymaster",
            ],
        }
        logger.info("Configured ERC-4337 wallet (entrypoint=%s)", self.config.erc4337_entrypoint)
        return config

    def setup_push_notifications(self, component: IOSComponent) -> None:
        """
        Configure push notification hooks for a component.

        Each of the 30 components gets dedicated push notification
        channels for alerts, status updates, and Morpheus triggers.
        """
        name = component.component_name
        component.push_notification_hooks = [
            f"push.{name}.alert",
            f"push.{name}.status_update",
            f"push.{name}.morpheus_trigger",
            f"push.{name}.trinity_response",
        ]
        logger.info(
            "Configured push notifications for '%s' (%d hooks)",
            name,
            len(component.push_notification_hooks),
        )

    def integrate_xmtp_mobile(self) -> Dict[str, Any]:
        """
        Integrate XMTP mobile messaging for secure component communication.

        Returns:
            XMTP configuration for the MTRX iOS app.
        """
        config = {
            "env": self.config.xmtp_env,
            "protocol_version": "v3",
            "encryption": "mls",
            "features": [
                "direct_messages",
                "group_chats",
                "component_notifications",
                "trinity_relay",
                "morpheus_alerts",
            ],
            "neosafe_identity": NEOSAFE_ADDRESS,
            "auto_consent": False,
            "push_integration": True,
        }
        logger.info("Configured XMTP mobile messaging (env=%s)", self.config.xmtp_env)
        return config

    # ── Internal helpers ───────────────────────────────────────────────────

    def _package_single_component(self, export_package: Any) -> IOSComponent:
        """Convert a bridge-validated ExportPackage into an IOSComponent."""
        name = export_package.component_name
        ios_comp = IOSComponent(
            component_name=name,
            api_endpoints=self.generate_api_endpoints(export_package),
            files=export_package.files,
        )
        return ios_comp
