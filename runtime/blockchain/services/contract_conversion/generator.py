"""
Solidity Generator — Generates Deployable Smart Contracts
=========================================================

Transforms a ``ParsedContract`` into a complete, deployable Solidity source
file.  The generated contract inherits from the platform's
``ContractConversion`` base and encodes all extracted parties, conditions,
payment logic, triggers, and dispute-resolution routing.

Bilateral disputes are always routed to **Component 30**.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import tempfile
import textwrap
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from runtime.blockchain.services.contract_conversion.parser import (
    Condition,
    ConditionType,
    DisputeMethod,
    DisputeResolution,
    ParsedContract,
    Party,
    PartyRole,
    PaymentFrequency,
    PaymentTerms,
    Trigger,
    TriggerType,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

NEOSAFE_ADDRESS: str = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

_SOLIDITY_HEADER: str = textwrap.dedent("""\
    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.19;

    import "@openzeppelin/contracts/access/Ownable.sol";
    import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
""")

# Maps PartyRole -> Solidity variable-name fragment.
_ROLE_VAR_NAME: Dict[PartyRole, str] = {
    PartyRole.LANDLORD: "landlord",
    PartyRole.TENANT: "tenant",
    PartyRole.EMPLOYER: "employer",
    PartyRole.EMPLOYEE: "employee",
    PartyRole.LICENSOR: "licensor",
    PartyRole.LICENSEE: "licensee",
    PartyRole.SERVICE_PROVIDER: "serviceProvider",
    PartyRole.CLIENT: "client",
    PartyRole.PARTNER: "partner",
    PartyRole.BUYER: "buyer",
    PartyRole.SELLER: "seller",
    PartyRole.ARTIST: "artist",
    PartyRole.INVESTOR: "investor",
    PartyRole.ESCROW_AGENT: "escrowAgent",
    PartyRole.OTHER: "partyOther",
}


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------

@dataclass
class CompilationResult:
    """Result of a ``solc`` compilation attempt."""
    success: bool
    abi: Optional[List[Dict[str, Any]]] = None
    bytecode: Optional[str] = None
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    source: str = ""


@dataclass
class ValidationResult:
    """Result of a post-compilation validation pass."""
    is_valid: bool
    issues: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Generator Implementation
# ---------------------------------------------------------------------------

class SolidityGenerator:
    """
    Generates complete, deployable Solidity source from a ``ParsedContract``.

    The output contract:
      * Defines address state for every extracted party.
      * Encodes conditions as require-guarded modifiers or on-chain flags.
      * Generates payment logic honouring the parsed schedule.
      * Creates trigger functions (time-based, event-based, etc.).
      * Routes bilateral disputes to Component 30.
      * Applies tier-based revenue sharing + 2.5 % PAC to NeoSafe.

    Usage::

        gen = SolidityGenerator()
        solidity_source = gen.generate(parsed_contract)
        result = gen.compile_contract(solidity_source)
        validation = gen.validate_contract(result)
    """

    def __init__(self, solc_path: str = "solc") -> None:
        """
        Parameters
        ----------
        solc_path : str
            Path or alias of the ``solc`` compiler binary.
        """
        self._solc_path: str = solc_path

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def generate(self, parsed_contract: ParsedContract) -> str:
        """
        Generate a complete Solidity source file from *parsed_contract*.

        Parameters
        ----------
        parsed_contract : ParsedContract
            Output of ``ContractParser.parse_document()``.

        Returns
        -------
        str
            Complete Solidity source code ready for compilation.

        Raises
        ------
        ValueError
            If the parsed contract contains critical validation errors.
        """
        if not parsed_contract.parties:
            raise ValueError("Cannot generate Solidity: no parties extracted.")

        contract_name = self._to_contract_name(parsed_contract.title)

        sections: List[str] = [
            _SOLIDITY_HEADER,
            self._generate_contract_open(contract_name, parsed_contract),
            self._generate_constants(),
            self._generate_enums(parsed_contract),
            self._generate_state_variables(parsed_contract),
            self._generate_events(parsed_contract),
            self._generate_modifiers(parsed_contract),
            self._generate_constructor(parsed_contract),
            self._generate_conditions(parsed_contract.conditions),
            self._generate_payment_logic(parsed_contract.payment_terms),
            self._generate_trigger_logic(parsed_contract.triggers),
            self._generate_dispute_routing(parsed_contract.dispute_resolution),
            self._generate_revenue_enforcement(),
            self._generate_utility_functions(parsed_contract),
            self._generate_contract_close(),
        ]

        return "\n".join(sections)

    def generate_conditions(self, conditions: List[Condition]) -> str:
        """Generate Solidity code for the supplied conditions list."""
        return self._generate_conditions(
            ParsedContract(
                title="",
                parties=[],
                conditions=conditions,
                payment_terms=PaymentTerms(),
                triggers=[],
                dispute_resolution=DisputeResolution(),
                raw_text="",
                document_hash="",
            ).conditions
        )

    def generate_payment_logic(self, terms: PaymentTerms) -> str:
        """Generate Solidity payment logic for the given terms."""
        return self._generate_payment_logic(terms)

    def generate_trigger_logic(self, triggers: List[Trigger]) -> str:
        """Generate Solidity trigger functions for the given triggers."""
        return self._generate_trigger_logic(triggers)

    def generate_dispute_routing(self, resolution: DisputeResolution) -> str:
        """Generate Solidity dispute routing for the given resolution."""
        return self._generate_dispute_routing(resolution)

    def compile_contract(self, solidity_source: str) -> CompilationResult:
        """
        Compile *solidity_source* using the ``solc`` compiler.

        Parameters
        ----------
        solidity_source : str
            Complete Solidity source string.

        Returns
        -------
        CompilationResult
            Contains ABI, bytecode, errors, and warnings.
        """
        result = CompilationResult(success=False, source=solidity_source)

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".sol", delete=False
        ) as tmp:
            tmp.write(solidity_source)
            tmp_path = tmp.name

        try:
            standard_input = {
                "language": "Solidity",
                "sources": {
                    "Contract.sol": {"content": solidity_source}
                },
                "settings": {
                    "outputSelection": {
                        "*": {
                            "*": ["abi", "evm.bytecode.object"]
                        }
                    },
                    "optimizer": {"enabled": True, "runs": 200},
                },
            }

            proc = subprocess.run(
                [self._solc_path, "--standard-json"],
                input=json.dumps(standard_input),
                capture_output=True,
                text=True,
                timeout=60,
            )

            output = json.loads(proc.stdout) if proc.stdout else {}

            # Collect errors and warnings.
            for entry in output.get("errors", []):
                msg = entry.get("formattedMessage", entry.get("message", ""))
                if entry.get("severity") == "error":
                    result.errors.append(msg)
                else:
                    result.warnings.append(msg)

            # Extract ABI + bytecode from the first contract found.
            contracts = output.get("contracts", {})
            for file_contracts in contracts.values():
                for name, data in file_contracts.items():
                    result.abi = data.get("abi")
                    evm = data.get("evm", {})
                    result.bytecode = evm.get("bytecode", {}).get("object")
                    break
                break

            result.success = len(result.errors) == 0 and result.bytecode is not None

        except FileNotFoundError:
            result.errors.append(
                f"Solidity compiler not found at '{self._solc_path}'. "
                "Install solc or provide the correct path."
            )
        except subprocess.TimeoutExpired:
            result.errors.append("Compilation timed out after 60 seconds.")
        except json.JSONDecodeError as exc:
            result.errors.append(f"Failed to parse compiler output: {exc}")
        finally:
            Path(tmp_path).unlink(missing_ok=True)

        return result

    def validate_contract(self, compiled: CompilationResult) -> ValidationResult:
        """
        Run post-compilation validation checks on *compiled*.

        Checks
        ------
        * Compilation succeeded without errors.
        * ABI is non-empty and contains expected function signatures.
        * Bytecode is present and non-trivial.
        * NeoSafe address is referenced in the source.
        * Revenue enforcement functions are present.

        Parameters
        ----------
        compiled : CompilationResult
            Output of ``compile_contract()``.

        Returns
        -------
        ValidationResult
        """
        issues: List[str] = []

        if not compiled.success:
            issues.append("Compilation failed. Fix errors before deployment.")
            for err in compiled.errors:
                issues.append(f"  solc: {err}")
            return ValidationResult(is_valid=False, issues=issues)

        # ABI checks.
        if not compiled.abi:
            issues.append("ABI is empty — the compiled output may be incomplete.")
        else:
            abi_names = {
                entry.get("name", "") for entry in compiled.abi if "name" in entry
            }
            required_functions = {
                "recordRevenue", "calculateTierShare",
                "routeToNeoSafe", "fileDispute",
            }
            missing = required_functions - abi_names
            if missing:
                issues.append(
                    f"ABI missing expected functions: {', '.join(sorted(missing))}"
                )

        # Bytecode sanity.
        if not compiled.bytecode or len(compiled.bytecode) < 20:
            issues.append("Bytecode appears too short or empty.")

        # NeoSafe reference in source.
        if NEOSAFE_ADDRESS.lower() not in compiled.source.lower():
            issues.append("NeoSafe address not found in source code.")

        return ValidationResult(
            is_valid=len(issues) == 0,
            issues=issues,
        )

    # ------------------------------------------------------------------
    # Private Code-Generation Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _to_contract_name(title: str) -> str:
        """Convert a human title to a valid Solidity contract name."""
        cleaned = re.sub(r"[^a-zA-Z0-9 ]", "", title)
        parts = cleaned.strip().split()
        name = "".join(p.capitalize() for p in parts) if parts else "GeneratedContract"
        if not name[0].isalpha():
            name = "Contract" + name
        return name

    def _generate_contract_open(
        self, name: str, pc: ParsedContract
    ) -> str:
        doc_hash = pc.document_hash[:16] if pc.document_hash else "N/A"
        return textwrap.dedent(f"""\
            /**
             * @title {name}
             * @notice Auto-generated from document hash {doc_hash}...
             * @dev Generated by Component 1 - Smart Contract Conversion Service
             */
            contract {name} is Ownable, ReentrancyGuard {{
        """)

    @staticmethod
    def _generate_constants() -> str:
        return textwrap.dedent(f"""\
                // ---- Constants ----
                address public constant NEOSAFE = {NEOSAFE_ADDRESS};
                uint256 public constant TIER1_SHARE_BPS = 1000;
                uint256 public constant TIER2_SHARE_BPS = 500;
                uint256 public constant TIER3_SHARE_BPS = 250;
                uint256 public constant PAC_BPS = 250;
                uint256 private constant BPS_DENOMINATOR = 10_000;
        """)

    @staticmethod
    def _generate_enums(pc: ParsedContract) -> str:
        lines = [
            "    // ---- Enums ----",
            "    enum ContractState { Active, Paused, Terminated, Disputed }",
            "    enum Tier { TIER_1, TIER_2, TIER_3 }",
            "",
        ]
        return "\n".join(lines) + "\n"

    def _generate_state_variables(self, pc: ParsedContract) -> str:
        lines = ["    // ---- State Variables ----"]
        lines.append("    ContractState public contractState;")
        lines.append("    address public rexhepiGate;")
        lines.append(f"    bytes32 public documentHash;")
        lines.append("    uint256 public createdAt;")
        lines.append("")

        # Party addresses.
        seen_vars: set = set()
        for i, party in enumerate(pc.parties):
            var_name = _ROLE_VAR_NAME.get(party.role, f"party{i}")
            if var_name in seen_vars:
                var_name = f"{var_name}_{i}"
            seen_vars.add(var_name)
            lines.append(f"    address public {var_name};")

        # Payment state.
        lines.append("")
        lines.append("    uint256 public totalPaid;")
        lines.append("    uint256 public totalDue;")
        lines.append("    bool public paymentComplete;")

        # Condition flags.
        lines.append("")
        for i, cond in enumerate(pc.conditions):
            lines.append(f"    bool public condition_{i}_met;")

        lines.append("")
        return "\n".join(lines) + "\n"

    def _generate_events(self, pc: ParsedContract) -> str:
        lines = [
            "    // ---- Events ----",
            "    event PaymentMade(address indexed from, address indexed to, uint256 amount);",
            "    event PaymentReleased(address indexed to, uint256 amount);",
            "    event ConditionMet(uint256 indexed conditionIndex);",
            "    event ContractTerminated(address indexed by, uint256 timestamp);",
            "    event DisputeFiled(address indexed filedBy, string reason);",
            "    event FundsRoutedToNeoSafe(uint256 tierShare, uint256 pacShare);",
            "    event TriggerExecuted(uint256 indexed triggerIndex, string action);",
            "    event RevenueRecorded(address indexed user, uint256 amount, Tier tier);",
            "",
        ]
        return "\n".join(lines) + "\n"

    def _generate_modifiers(self, pc: ParsedContract) -> str:
        lines = [
            "    // ---- Modifiers ----",
            "    modifier onlyThroughRexhepiGate() {",
            '        require(msg.sender == rexhepiGate, "Caller is not the Rexhepi gate");',
            "        _;",
            "    }",
            "",
            "    modifier whenActive() {",
            '        require(contractState == ContractState.Active, "Contract is not active");',
            "        _;",
            "    }",
            "",
        ]
        return "\n".join(lines) + "\n"

    def _generate_constructor(self, pc: ParsedContract) -> str:
        lines = ["    // ---- Constructor ----"]
        params: List[str] = ["address _rexhepiGate"]
        seen_vars: set = set()
        var_map: List[Tuple[str, str]] = []

        for i, party in enumerate(pc.parties):
            var_name = _ROLE_VAR_NAME.get(party.role, f"party{i}")
            if var_name in seen_vars:
                var_name = f"{var_name}_{i}"
            seen_vars.add(var_name)
            param_name = f"_{var_name}"
            params.append(f"address {param_name}")
            var_map.append((var_name, param_name))

        if pc.payment_terms.total_amount is not None:
            params.append("uint256 _totalDue")

        param_str = ",\n        ".join(params)
        lines.append(f"    constructor(\n        {param_str}\n    ) Ownable() {{")
        lines.append('        require(_rexhepiGate != address(0), "Zero gate address");')
        lines.append("        rexhepiGate = _rexhepiGate;")
        lines.append(f'        documentHash = keccak256(abi.encodePacked("{pc.document_hash[:32]}"));')
        lines.append("        createdAt = block.timestamp;")
        lines.append("        contractState = ContractState.Active;")

        for var_name, param_name in var_map:
            lines.append(f"        {var_name} = {param_name};")

        if pc.payment_terms.total_amount is not None:
            lines.append("        totalDue = _totalDue;")

        lines.append("    }")
        lines.append("")
        return "\n".join(lines) + "\n"

    def _generate_conditions(self, conditions: List[Condition]) -> str:
        """Generate condition-checking and fulfillment functions."""
        lines = ["    // ---- Conditions ----"]

        for i, cond in enumerate(conditions):
            safe_desc = cond.description[:60].replace('"', "'")
            lines.append(f"    /// @notice Condition {i}: {safe_desc}")
            lines.append(
                f"    function fulfillCondition_{i}() external onlyThroughRexhepiGate whenActive {{"
            )
            lines.append(
                f'        require(!condition_{i}_met, "Condition {i} already fulfilled");'
            )
            lines.append(f"        condition_{i}_met = true;")
            lines.append(f"        emit ConditionMet({i});")
            lines.append("    }")
            lines.append("")

        # Aggregate check.
        if conditions:
            lines.append("    /// @notice Returns true when ALL conditions are met.")
            lines.append("    function allConditionsMet() public view returns (bool) {")
            checks = " && ".join(f"condition_{i}_met" for i in range(len(conditions)))
            lines.append(f"        return {checks};")
            lines.append("    }")
            lines.append("")

        return "\n".join(lines) + "\n"

    def _generate_payment_logic(self, terms: PaymentTerms) -> str:
        """Generate payment receipt, release, and late-fee logic."""
        lines = ["    // ---- Payment Logic ----"]

        # makePayment
        lines.append("    /// @notice Accept a payment into the contract.")
        lines.append(
            "    function makePayment() external payable whenActive nonReentrant {"
        )
        lines.append('        require(msg.value > 0, "Payment must be > 0");')
        lines.append("        totalPaid += msg.value;")
        lines.append("        if (totalDue > 0 && totalPaid >= totalDue) {")
        lines.append("            paymentComplete = true;")
        lines.append("        }")
        lines.append("        emit PaymentMade(msg.sender, address(this), msg.value);")
        lines.append("")
        lines.append("        // Revenue enforcement — tier share + PAC to NeoSafe")
        lines.append("        _enforceRevenueShare(msg.sender, msg.value);")
        lines.append("    }")
        lines.append("")

        # releasePayment
        lines.append("    /// @notice Release escrowed funds to a recipient.")
        lines.append(
            "    function releasePayment(address payable _to, uint256 _amount)"
        )
        lines.append(
            "        external onlyThroughRexhepiGate whenActive nonReentrant"
        )
        lines.append("    {")
        lines.append('        require(_to != address(0), "Zero address");')
        lines.append(
            '        require(address(this).balance >= _amount, "Insufficient balance");'
        )
        lines.append('        (bool sent, ) = _to.call{value: _amount}("");')
        lines.append('        require(sent, "Transfer failed");')
        lines.append("        emit PaymentReleased(_to, _amount);")
        lines.append("    }")
        lines.append("")

        # Late fee calculation.
        if terms.late_fee_percent is not None:
            bps = int(terms.late_fee_percent * 100)
            lines.append(
                f"    uint256 public constant LATE_FEE_BPS = {bps};"
            )
            lines.append("")
            lines.append("    /// @notice Calculate the late fee for an overdue amount.")
            lines.append(
                "    function calculateLateFee(uint256 _overdue) public pure returns (uint256) {"
            )
            lines.append(
                f"        return (_overdue * LATE_FEE_BPS) / BPS_DENOMINATOR;"
            )
            lines.append("    }")
            lines.append("")

        # Escrow deposit.
        if terms.escrow_required and terms.deposit_amount is not None:
            deposit_wei = f"{int(terms.deposit_amount)} ether"
            lines.append(
                f"    uint256 public constant REQUIRED_DEPOSIT = {deposit_wei};"
            )
            lines.append(
                "    bool public depositReceived;"
            )
            lines.append("")
            lines.append("    /// @notice Accept the escrow deposit.")
            lines.append("    function payDeposit() external payable whenActive {")
            lines.append(
                '        require(msg.value >= REQUIRED_DEPOSIT, "Deposit too low");'
            )
            lines.append("        depositReceived = true;")
            lines.append("    }")
            lines.append("")

        return "\n".join(lines) + "\n"

    def _generate_trigger_logic(self, triggers: List[Trigger]) -> str:
        """Generate on-chain trigger functions."""
        lines = ["    // ---- Triggers ----"]

        for i, trigger in enumerate(triggers):
            safe_desc = trigger.description[:60].replace('"', "'")
            fn_name = f"executeTrigger_{i}"
            lines.append(f"    /// @notice Trigger {i}: {safe_desc}")

            if trigger.trigger_type == TriggerType.TIME_BASED:
                lines.append(
                    f"    function {fn_name}() external onlyThroughRexhepiGate whenActive {{"
                )
                if "date" in trigger.parameters:
                    lines.append(
                        f"        // Time guard would check block.timestamp against target"
                    )
                lines.append(
                    f'        emit TriggerExecuted({i}, "{trigger.action}");'
                )
                lines.append(
                    f"        _{trigger.action}();"
                ) if trigger.action != "custom_action" else None
                lines.append("    }")
            elif trigger.trigger_type == TriggerType.CONDITION_MET:
                lines.append(
                    f"    function {fn_name}() external onlyThroughRexhepiGate whenActive {{"
                )
                lines.append(
                    '        require(allConditionsMet(), "Conditions not met");'
                    if triggers else ""
                )
                lines.append(
                    f'        emit TriggerExecuted({i}, "{trigger.action}");'
                )
                lines.append("    }")
            else:
                lines.append(
                    f"    function {fn_name}() external onlyThroughRexhepiGate whenActive {{"
                )
                lines.append(
                    f'        emit TriggerExecuted({i}, "{trigger.action}");'
                )
                lines.append("    }")

            lines.append("")

        # Internal action stubs.
        action_set = {t.action for t in triggers if t.action != "custom_action"}
        for action in sorted(action_set):
            lines.append(f"    function _{action}() internal {{")
            if action == "release_payment":
                lines.append("        // Release payment logic handled by releasePayment()")
            elif action == "terminate_contract":
                lines.append("        contractState = ContractState.Terminated;")
                lines.append("        emit ContractTerminated(msg.sender, block.timestamp);")
            elif action == "emit_notification":
                lines.append("        // Off-chain notification emitted via event")
            elif action == "apply_penalty":
                lines.append("        // Penalty application logic")
            elif action == "renew_contract":
                lines.append("        // Renewal logic — extend expiry timestamps")
            lines.append("    }")
            lines.append("")

        return "\n".join(lines) + "\n"

    def _generate_dispute_routing(self, resolution: DisputeResolution) -> str:
        """
        Generate dispute-filing logic.

        ALL bilateral disputes route to Component 30.
        Never routes to Component 19.
        """
        lines = [
            "    // ---- Dispute Resolution (routes to Component 30) ----",
            "    address public component30Address;",
            "",
            "    /// @notice File a bilateral dispute — always routed to Component 30.",
            "    function fileDispute(string calldata _reason)",
            "        external whenActive",
            "    {",
            "        contractState = ContractState.Disputed;",
            "        emit DisputeFiled(msg.sender, _reason);",
            "",
            "        // Route to Component 30 for bilateral dispute resolution.",
            "        if (component30Address != address(0)) {",
            '            (bool ok, ) = component30Address.call(',
            '                abi.encodeWithSignature(',
            '                    "receiveDispute(address,address,string)",',
            "                    address(this), msg.sender, _reason",
            "                )",
            "            );",
            '            require(ok, "Component 30 routing failed");',
            "        }",
            "    }",
            "",
            "    /// @notice Set the Component 30 dispute-handler address.",
            "    function setComponent30(address _addr) external onlyOwner {",
            '        require(_addr != address(0), "Zero address");',
            "        component30Address = _addr;",
            "    }",
            "",
        ]
        return "\n".join(lines) + "\n"

    def _generate_revenue_enforcement(self) -> str:
        """Generate internal revenue-share + PAC enforcement."""
        return textwrap.dedent("""\
            // ---- Revenue Enforcement ----
            mapping(address => Tier) public userTier;

            /// @dev Deducts tier share + 2.5% PAC and sends to NeoSafe.
            function _enforceRevenueShare(address _user, uint256 _amount) internal {
                uint256 tierBps;
                Tier tier = userTier[_user];
                if (tier == Tier.TIER_1) {
                    tierBps = TIER1_SHARE_BPS;
                } else if (tier == Tier.TIER_2) {
                    tierBps = TIER2_SHARE_BPS;
                } else {
                    tierBps = TIER3_SHARE_BPS;
                }

                uint256 tierShare = (_amount * tierBps) / BPS_DENOMINATOR;
                uint256 pacShare  = (_amount * PAC_BPS) / BPS_DENOMINATOR;
                uint256 total = tierShare + pacShare;

                if (total > 0 && address(this).balance >= total) {
                    (bool sent, ) = payable(NEOSAFE).call{value: total}("");
                    require(sent, "NeoSafe routing failed");
                    emit FundsRoutedToNeoSafe(tierShare, pacShare);
                }

                emit RevenueRecorded(_user, _amount, tier);
            }

            /// @notice Route an arbitrary amount to NeoSafe (admin).
            function routeToNeoSafe(uint256 _amount)
                external onlyThroughRexhepiGate nonReentrant
            {
                require(address(this).balance >= _amount, "Insufficient balance");
                (bool sent, ) = payable(NEOSAFE).call{value: _amount}("");
                require(sent, "Transfer to NeoSafe failed");
            }
        """)

    def _generate_utility_functions(self, pc: ParsedContract) -> str:
        """Generate helper / utility functions."""
        lines = [
            "    // ---- Utilities ----",
            "    /// @notice Terminate the contract.",
            "    function terminateContract()",
            "        external onlyThroughRexhepiGate whenActive",
            "    {",
            "        contractState = ContractState.Terminated;",
            "        emit ContractTerminated(msg.sender, block.timestamp);",
            "    }",
            "",
            "    /// @notice Pause the contract.",
            "    function pauseContract() external onlyThroughRexhepiGate {",
            "        contractState = ContractState.Paused;",
            "    }",
            "",
            "    /// @notice Resume a paused contract.",
            "    function resumeContract() external onlyThroughRexhepiGate {",
            '        require(contractState == ContractState.Paused, "Not paused");',
            "        contractState = ContractState.Active;",
            "    }",
            "",
            "    /// @notice Retrieve contract ETH balance.",
            "    function getBalance() external view returns (uint256) {",
            "        return address(this).balance;",
            "    }",
            "",
            "    receive() external payable {}",
            "    fallback() external payable {}",
            "",
        ]
        return "\n".join(lines) + "\n"

    @staticmethod
    def _generate_contract_close() -> str:
        return "}\n"
