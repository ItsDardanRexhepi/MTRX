"""
Contract Parser — Natural Language Contract Parsing Engine
==========================================================

Parses plain-language text or uploaded documents into a structured
``ParsedContract`` data object that the ``SolidityGenerator`` can consume.

Uses regex-based NLP heuristics complemented by keyword/phrase matching to
extract parties, conditions, payment terms, triggers, and dispute-resolution
clauses from arbitrary contract prose.
"""

from __future__ import annotations

import hashlib
import os
import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Data Models
# ---------------------------------------------------------------------------

class PartyRole(Enum):
    """Enumeration of common contractual roles."""
    LANDLORD = auto()
    TENANT = auto()
    EMPLOYER = auto()
    EMPLOYEE = auto()
    LICENSOR = auto()
    LICENSEE = auto()
    SERVICE_PROVIDER = auto()
    CLIENT = auto()
    PARTNER = auto()
    BUYER = auto()
    SELLER = auto()
    ARTIST = auto()
    INVESTOR = auto()
    ESCROW_AGENT = auto()
    OTHER = auto()


@dataclass
class Party:
    """A party to the contract."""
    name: str
    role: PartyRole
    address: Optional[str] = None          # wallet / physical address
    eth_address: Optional[str] = None      # 0x... on-chain address
    contact_info: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class ConditionType(Enum):
    """Type of contractual condition."""
    PRECONDITION = auto()
    ONGOING = auto()
    TERMINATION = auto()
    PENALTY = auto()
    FORCE_MAJEURE = auto()
    CUSTOM = auto()


@dataclass
class Condition:
    """A single contractual condition or clause."""
    description: str
    condition_type: ConditionType
    is_mandatory: bool = True
    penalty_clause: Optional[str] = None
    deadline: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class PaymentFrequency(Enum):
    """Frequency at which payments recur."""
    ONE_TIME = auto()
    DAILY = auto()
    WEEKLY = auto()
    BIWEEKLY = auto()
    MONTHLY = auto()
    QUARTERLY = auto()
    ANNUALLY = auto()
    ON_MILESTONE = auto()
    CUSTOM = auto()


@dataclass
class PaymentTerms:
    """Structured payment information extracted from the contract."""
    total_amount: Optional[float] = None
    currency: str = "ETH"
    frequency: PaymentFrequency = PaymentFrequency.ONE_TIME
    due_date: Optional[str] = None
    installment_amount: Optional[float] = None
    late_fee_percent: Optional[float] = None
    deposit_amount: Optional[float] = None
    escrow_required: bool = False
    milestones: List[Dict[str, Any]] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)


class TriggerType(Enum):
    """Types of on-chain triggers."""
    TIME_BASED = auto()
    EVENT_BASED = auto()
    ORACLE_BASED = auto()
    MANUAL = auto()
    CONDITION_MET = auto()
    CUSTOM = auto()


@dataclass
class Trigger:
    """An event or condition that triggers a contract action."""
    description: str
    trigger_type: TriggerType
    action: str
    parameters: Dict[str, Any] = field(default_factory=dict)
    metadata: Dict[str, Any] = field(default_factory=dict)


class DisputeMethod(Enum):
    """Dispute resolution methods."""
    ARBITRATION = auto()
    MEDIATION = auto()
    COMPONENT_30 = auto()      # bilateral dispute system
    COURT = auto()
    CUSTOM = auto()


@dataclass
class DisputeResolution:
    """Dispute-resolution clause extracted from the contract."""
    method: DisputeMethod = DisputeMethod.COMPONENT_30
    jurisdiction: Optional[str] = None
    arbitrator: Optional[str] = None
    escalation_steps: List[str] = field(default_factory=list)
    time_limit_days: Optional[int] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ParsedContract:
    """Fully parsed representation of a natural-language contract."""
    title: str
    parties: List[Party]
    conditions: List[Condition]
    payment_terms: PaymentTerms
    triggers: List[Trigger]
    dispute_resolution: DisputeResolution
    raw_text: str
    document_hash: str
    parsed_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    contract_type: Optional[str] = None
    effective_date: Optional[str] = None
    expiration_date: Optional[str] = None
    governing_law: Optional[str] = None
    confidentiality_clause: bool = False
    non_compete_clause: bool = False
    metadata: Dict[str, Any] = field(default_factory=dict)
    validation_errors: List[str] = field(default_factory=list)

    @property
    def is_valid(self) -> bool:
        """Return ``True`` when no validation errors are present."""
        return len(self.validation_errors) == 0


# ---------------------------------------------------------------------------
# Keyword / Phrase Banks
# ---------------------------------------------------------------------------

_ROLE_KEYWORDS: Dict[str, PartyRole] = {
    "landlord": PartyRole.LANDLORD,
    "lessor": PartyRole.LANDLORD,
    "tenant": PartyRole.TENANT,
    "lessee": PartyRole.TENANT,
    "renter": PartyRole.TENANT,
    "employer": PartyRole.EMPLOYER,
    "company": PartyRole.EMPLOYER,
    "employee": PartyRole.EMPLOYEE,
    "worker": PartyRole.EMPLOYEE,
    "contractor": PartyRole.SERVICE_PROVIDER,
    "licensor": PartyRole.LICENSOR,
    "licensee": PartyRole.LICENSEE,
    "service provider": PartyRole.SERVICE_PROVIDER,
    "provider": PartyRole.SERVICE_PROVIDER,
    "client": PartyRole.CLIENT,
    "customer": PartyRole.CLIENT,
    "partner": PartyRole.PARTNER,
    "buyer": PartyRole.BUYER,
    "purchaser": PartyRole.BUYER,
    "seller": PartyRole.SELLER,
    "vendor": PartyRole.SELLER,
    "artist": PartyRole.ARTIST,
    "creator": PartyRole.ARTIST,
    "investor": PartyRole.INVESTOR,
    "escrow agent": PartyRole.ESCROW_AGENT,
}

_FREQUENCY_KEYWORDS: Dict[str, PaymentFrequency] = {
    "one-time": PaymentFrequency.ONE_TIME,
    "one time": PaymentFrequency.ONE_TIME,
    "lump sum": PaymentFrequency.ONE_TIME,
    "daily": PaymentFrequency.DAILY,
    "weekly": PaymentFrequency.WEEKLY,
    "biweekly": PaymentFrequency.BIWEEKLY,
    "bi-weekly": PaymentFrequency.BIWEEKLY,
    "monthly": PaymentFrequency.MONTHLY,
    "quarterly": PaymentFrequency.QUARTERLY,
    "annually": PaymentFrequency.ANNUALLY,
    "yearly": PaymentFrequency.ANNUALLY,
    "per milestone": PaymentFrequency.ON_MILESTONE,
    "milestone": PaymentFrequency.ON_MILESTONE,
}

_CONDITION_KEYWORDS: Dict[str, ConditionType] = {
    "before": ConditionType.PRECONDITION,
    "prior to": ConditionType.PRECONDITION,
    "prerequisite": ConditionType.PRECONDITION,
    "condition precedent": ConditionType.PRECONDITION,
    "ongoing": ConditionType.ONGOING,
    "continuously": ConditionType.ONGOING,
    "at all times": ConditionType.ONGOING,
    "throughout": ConditionType.ONGOING,
    "terminate": ConditionType.TERMINATION,
    "termination": ConditionType.TERMINATION,
    "cancel": ConditionType.TERMINATION,
    "end of agreement": ConditionType.TERMINATION,
    "penalty": ConditionType.PENALTY,
    "fine": ConditionType.PENALTY,
    "liquidated damages": ConditionType.PENALTY,
    "force majeure": ConditionType.FORCE_MAJEURE,
    "act of god": ConditionType.FORCE_MAJEURE,
}

_TRIGGER_KEYWORDS: Dict[str, TriggerType] = {
    "on date": TriggerType.TIME_BASED,
    "after": TriggerType.TIME_BASED,
    "before": TriggerType.TIME_BASED,
    "deadline": TriggerType.TIME_BASED,
    "upon": TriggerType.EVENT_BASED,
    "when": TriggerType.EVENT_BASED,
    "if": TriggerType.CONDITION_MET,
    "provided that": TriggerType.CONDITION_MET,
    "oracle": TriggerType.ORACLE_BASED,
    "data feed": TriggerType.ORACLE_BASED,
    "manually": TriggerType.MANUAL,
    "at discretion": TriggerType.MANUAL,
}


# ---------------------------------------------------------------------------
# Parser Implementation
# ---------------------------------------------------------------------------

class ContractParser:
    """
    Parses natural-language contract documents into a structured
    ``ParsedContract`` object suitable for Solidity code generation.

    Supports raw text input as well as file paths (.txt, .md, .pdf stubs).
    """

    # Regex helpers
    _PARTY_PATTERN = re.compile(
        r"(?:between|by and between|party\s*[:\-]?)\s+"
        r"([A-Z][\w\s,.]+?)(?:\s*\(.*?\))?\s*"
        r"(?:and|,)\s+"
        r"([A-Z][\w\s,.]+?)(?:\s*\(.*?\))?",
        re.IGNORECASE | re.DOTALL,
    )
    _AMOUNT_PATTERN = re.compile(
        r"(\d+(?:[.,]\d+)?)\s*(?:ETH|ether|wei|USD|dollars?|\$)",
        re.IGNORECASE,
    )
    _DATE_PATTERN = re.compile(
        r"\b(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b"
        r"|\b(\w+ \d{1,2},?\s*\d{4})\b",
        re.IGNORECASE,
    )
    _ETH_ADDRESS_PATTERN = re.compile(r"0x[0-9a-fA-F]{40}")
    _SECTION_PATTERN = re.compile(
        r"(?:^|\n)\s*(?:section|article|clause|\d+\.)\s*[:\-.\s]*(.+)",
        re.IGNORECASE,
    )

    def __init__(self) -> None:
        self._supported_extensions: Tuple[str, ...] = (".txt", ".md", ".text")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def parse_document(self, text_or_file: str) -> ParsedContract:
        """
        Parse a contract document from raw text or a file path.

        Parameters
        ----------
        text_or_file : str
            Either the full text of the contract or a filesystem path
            pointing to a supported document file.

        Returns
        -------
        ParsedContract
            Structured representation of the parsed contract.

        Raises
        ------
        FileNotFoundError
            If *text_or_file* looks like a path but does not exist.
        ValueError
            If the file extension is unsupported.
        """
        raw_text = self._load_text(text_or_file)
        doc_hash = hashlib.sha256(raw_text.encode("utf-8")).hexdigest()

        parties = self.extract_parties(raw_text)
        conditions = self.extract_conditions(raw_text)
        payment_terms = self.extract_payment_terms(raw_text)
        triggers = self.extract_triggers(raw_text)
        dispute_resolution = self.extract_dispute_resolution(raw_text)
        title = self._extract_title(raw_text)
        contract_type = self._detect_contract_type(raw_text)
        effective_date = self._extract_effective_date(raw_text)
        expiration_date = self._extract_expiration_date(raw_text)
        governing_law = self._extract_governing_law(raw_text)
        confidentiality = self._has_clause(raw_text, [
            "confidentiality", "non-disclosure", "nda", "proprietary information",
        ])
        non_compete = self._has_clause(raw_text, [
            "non-compete", "noncompete", "non compete", "restrictive covenant",
        ])

        parsed = ParsedContract(
            title=title,
            parties=parties,
            conditions=conditions,
            payment_terms=payment_terms,
            triggers=triggers,
            dispute_resolution=dispute_resolution,
            raw_text=raw_text,
            document_hash=doc_hash,
            contract_type=contract_type,
            effective_date=effective_date,
            expiration_date=expiration_date,
            governing_law=governing_law,
            confidentiality_clause=confidentiality,
            non_compete_clause=non_compete,
        )

        parsed.validation_errors = self._validate(parsed)
        return parsed

    def extract_parties(self, text: str) -> List[Party]:
        """
        Extract contracting parties from *text*.

        Uses pattern matching to find named parties and attempts to assign
        a ``PartyRole`` to each based on surrounding context keywords.
        """
        parties: List[Party] = []
        seen_names: set = set()

        # Attempt structured "between X and Y" extraction.
        for match in self._PARTY_PATTERN.finditer(text):
            for group_text in match.groups():
                if group_text:
                    name = group_text.strip().rstrip(",. ")
                    if name and name.lower() not in seen_names:
                        role = self._infer_role(text, name)
                        eth_addr = self._find_nearby_eth_address(text, name)
                        parties.append(Party(
                            name=name,
                            role=role,
                            eth_address=eth_addr,
                        ))
                        seen_names.add(name.lower())

        # Fallback: look for explicit role labels like "Landlord: John Doe".
        role_label_pattern = re.compile(
            r"(" + "|".join(re.escape(k) for k in _ROLE_KEYWORDS) + r")"
            r"\s*[:\-]\s*([A-Z][\w\s,.]+)",
            re.IGNORECASE,
        )
        for m in role_label_pattern.finditer(text):
            role_word = m.group(1).strip().lower()
            name = m.group(2).strip().rstrip(",. ")
            if name.lower() not in seen_names:
                role = _ROLE_KEYWORDS.get(role_word, PartyRole.OTHER)
                eth_addr = self._find_nearby_eth_address(text, name)
                parties.append(Party(name=name, role=role, eth_address=eth_addr))
                seen_names.add(name.lower())

        # If still empty, try a simpler heuristic: first two capitalised names.
        if not parties:
            cap_names = re.findall(r"\b([A-Z][a-z]+ [A-Z][a-z]+)\b", text)
            for cn in cap_names[:2]:
                if cn.lower() not in seen_names:
                    parties.append(Party(name=cn, role=PartyRole.OTHER))
                    seen_names.add(cn.lower())

        return parties

    def extract_conditions(self, text: str) -> List[Condition]:
        """
        Extract contractual conditions / clauses from *text*.

        Splits the document into sentences and classifies each one that
        contains recognisable condition language.
        """
        conditions: List[Condition] = []
        sentences = self._split_sentences(text)

        for sentence in sentences:
            lower = sentence.lower()
            matched_type: Optional[ConditionType] = None

            for keyword, ctype in _CONDITION_KEYWORDS.items():
                if keyword in lower:
                    matched_type = ctype
                    break

            if matched_type is None:
                # Look for imperative obligation language.
                if any(w in lower for w in ("shall", "must", "obligated", "required to")):
                    matched_type = ConditionType.ONGOING
                elif any(w in lower for w in ("may terminate", "right to cancel")):
                    matched_type = ConditionType.TERMINATION

            if matched_type is not None:
                is_mandatory = any(
                    w in lower for w in ("shall", "must", "required", "obligated")
                )
                penalty = self._extract_penalty(sentence)
                deadline = self._extract_nearest_date(sentence)

                conditions.append(Condition(
                    description=sentence.strip(),
                    condition_type=matched_type,
                    is_mandatory=is_mandatory,
                    penalty_clause=penalty,
                    deadline=deadline,
                ))

        return conditions

    def extract_payment_terms(self, text: str) -> PaymentTerms:
        """
        Extract payment-related terms from *text*.

        Looks for monetary amounts, payment frequencies, due dates,
        late-fee percentages, deposits, and milestone schedules.
        """
        terms = PaymentTerms()

        # Currency detection
        if re.search(r"\b(?:USD|dollars?|\$)\b", text, re.IGNORECASE):
            terms.currency = "USD"
        elif re.search(r"\b(?:ETH|ether)\b", text, re.IGNORECASE):
            terms.currency = "ETH"

        # Extract amounts
        amounts = self._AMOUNT_PATTERN.findall(text)
        float_amounts = sorted(
            [float(a.replace(",", "")) for a in amounts], reverse=True
        )
        if float_amounts:
            terms.total_amount = float_amounts[0]
            if len(float_amounts) > 1:
                terms.installment_amount = float_amounts[1]

        # Payment frequency
        lower = text.lower()
        for keyword, freq in _FREQUENCY_KEYWORDS.items():
            if keyword in lower:
                terms.frequency = freq
                break

        # Due date
        dates = self._DATE_PATTERN.findall(text)
        if dates:
            terms.due_date = dates[0][0] or dates[0][1]

        # Late fee
        late_match = re.search(
            r"late\s+(?:fee|penalty|charge)\s*(?:of)?\s*(\d+(?:\.\d+)?)\s*%",
            text, re.IGNORECASE,
        )
        if late_match:
            terms.late_fee_percent = float(late_match.group(1))

        # Deposit
        deposit_match = re.search(
            r"deposit\s*(?:of)?\s*(\d+(?:[.,]\d+)?)\s*(?:ETH|ether|USD|dollars?|\$)",
            text, re.IGNORECASE,
        )
        if deposit_match:
            terms.deposit_amount = float(deposit_match.group(1).replace(",", ""))

        # Escrow
        terms.escrow_required = bool(
            re.search(r"\bescrow\b", text, re.IGNORECASE)
        )

        # Milestones
        milestone_pattern = re.compile(
            r"milestone\s*(\d+)\s*[:\-]\s*(.+?)(?:\s*[\-:]\s*(\d+(?:[.,]\d+)?)\s*(?:ETH|USD|\$))?(?:\.|;|$)",
            re.IGNORECASE,
        )
        for mm in milestone_pattern.finditer(text):
            ms: Dict[str, Any] = {
                "number": int(mm.group(1)),
                "description": mm.group(2).strip(),
            }
            if mm.group(3):
                ms["amount"] = float(mm.group(3).replace(",", ""))
            terms.milestones.append(ms)

        return terms

    def extract_triggers(self, text: str) -> List[Trigger]:
        """
        Extract event triggers that should map to on-chain actions.
        """
        triggers: List[Trigger] = []
        sentences = self._split_sentences(text)

        for sentence in sentences:
            lower = sentence.lower()
            matched_type: Optional[TriggerType] = None

            for keyword, ttype in _TRIGGER_KEYWORDS.items():
                if keyword in lower:
                    matched_type = ttype
                    break

            if matched_type is not None:
                action = self._infer_trigger_action(sentence)
                params: Dict[str, Any] = {}
                date = self._extract_nearest_date(sentence)
                if date:
                    params["date"] = date
                amounts = self._AMOUNT_PATTERN.findall(sentence)
                if amounts:
                    params["amount"] = float(amounts[0].replace(",", ""))

                triggers.append(Trigger(
                    description=sentence.strip(),
                    trigger_type=matched_type,
                    action=action,
                    parameters=params,
                ))

        return triggers

    def extract_dispute_resolution(self, text: str) -> DisputeResolution:
        """
        Extract the dispute-resolution clause.

        Defaults to ``DisputeMethod.COMPONENT_30`` (bilateral dispute
        routing) when no explicit method is found.
        """
        resolution = DisputeResolution()
        lower = text.lower()

        if "arbitration" in lower:
            resolution.method = DisputeMethod.ARBITRATION
        elif "mediation" in lower:
            resolution.method = DisputeMethod.MEDIATION
        elif any(w in lower for w in ("court", "litigation", "lawsuit")):
            resolution.method = DisputeMethod.COURT
        else:
            # Default: route all bilateral disputes to Component 30.
            resolution.method = DisputeMethod.COMPONENT_30

        # Jurisdiction
        juris_match = re.search(
            r"(?:governed?\s+by|jurisdiction\s+of|laws?\s+of)\s+(?:the\s+)?(.+?)(?:\.|;|$)",
            text, re.IGNORECASE,
        )
        if juris_match:
            resolution.jurisdiction = juris_match.group(1).strip()

        # Time limit
        time_match = re.search(
            r"(\d+)\s*(?:days?|business days?)\s*(?:to\s+)?(?:file|submit|raise|initiate)",
            text, re.IGNORECASE,
        )
        if time_match:
            resolution.time_limit_days = int(time_match.group(1))

        # Escalation steps
        escalation_pattern = re.compile(
            r"(?:step|stage|level)\s*(\d+)\s*[:\-]\s*(.+?)(?:\.|;|$)",
            re.IGNORECASE,
        )
        for em in escalation_pattern.finditer(text):
            resolution.escalation_steps.append(em.group(2).strip())

        return resolution

    # ------------------------------------------------------------------
    # Private Helpers
    # ------------------------------------------------------------------

    def _load_text(self, text_or_file: str) -> str:
        """Load text from a file path or return raw text directly."""
        candidate = text_or_file.strip()
        if len(candidate) < 500 and os.path.sep in candidate:
            path = Path(candidate)
            if path.exists():
                ext = path.suffix.lower()
                if ext not in self._supported_extensions:
                    raise ValueError(
                        f"Unsupported file extension '{ext}'. "
                        f"Supported: {self._supported_extensions}"
                    )
                return path.read_text(encoding="utf-8")
            else:
                raise FileNotFoundError(f"Contract file not found: {candidate}")
        return text_or_file

    def _extract_title(self, text: str) -> str:
        """Extract a title from the first heading-like line."""
        for line in text.strip().splitlines()[:5]:
            stripped = line.strip().strip("#").strip()
            if stripped and len(stripped) < 200:
                return stripped
        return "Untitled Contract"

    def _detect_contract_type(self, text: str) -> Optional[str]:
        """Heuristically detect the contract type."""
        lower = text.lower()
        type_map = {
            "rental": ["rental", "lease", "tenancy", "rent"],
            "employment": ["employment", "hire", "salary", "employee"],
            "service": ["service agreement", "consulting", "freelance", "scope of work"],
            "partnership": ["partnership", "joint venture", "profit sharing"],
            "licensing": ["license", "licensing", "intellectual property", "royalt"],
            "royalty": ["royalty", "royalties", "music rights", "publishing rights"],
            "escrow": ["escrow", "held in trust", "escrow agent"],
        }
        for ctype, keywords in type_map.items():
            if any(kw in lower for kw in keywords):
                return ctype
        return None

    def _extract_effective_date(self, text: str) -> Optional[str]:
        """Extract the effective / start date."""
        m = re.search(
            r"(?:effective|commenc|start)\s*(?:date|on|from)?\s*[:\-]?\s*"
            r"(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\w+ \d{1,2},?\s*\d{4})",
            text, re.IGNORECASE,
        )
        return m.group(1).strip() if m else None

    def _extract_expiration_date(self, text: str) -> Optional[str]:
        """Extract the expiration / end date."""
        m = re.search(
            r"(?:expir|end|terminat)\w*\s*(?:date|on)?\s*[:\-]?\s*"
            r"(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\w+ \d{1,2},?\s*\d{4})",
            text, re.IGNORECASE,
        )
        return m.group(1).strip() if m else None

    def _extract_governing_law(self, text: str) -> Optional[str]:
        """Extract the governing law / jurisdiction."""
        m = re.search(
            r"(?:governed?\s+by\s+(?:the\s+)?laws?\s+of|jurisdiction\s*[:\-]?)\s+(.+?)(?:\.|;|$)",
            text, re.IGNORECASE,
        )
        return m.group(1).strip() if m else None

    @staticmethod
    def _has_clause(text: str, keywords: List[str]) -> bool:
        lower = text.lower()
        return any(kw in lower for kw in keywords)

    def _infer_role(self, full_text: str, party_name: str) -> PartyRole:
        """Infer the role of a party from surrounding context."""
        window = 300
        idx = full_text.lower().find(party_name.lower())
        if idx == -1:
            return PartyRole.OTHER
        start = max(0, idx - window)
        end = min(len(full_text), idx + len(party_name) + window)
        context = full_text[start:end].lower()

        for keyword, role in _ROLE_KEYWORDS.items():
            if keyword in context:
                return role
        return PartyRole.OTHER

    def _find_nearby_eth_address(self, text: str, party_name: str) -> Optional[str]:
        """Find an Ethereum address near the party's name."""
        idx = text.lower().find(party_name.lower())
        if idx == -1:
            return None
        window_start = max(0, idx - 200)
        window_end = min(len(text), idx + len(party_name) + 200)
        snippet = text[window_start:window_end]
        m = self._ETH_ADDRESS_PATTERN.search(snippet)
        return m.group(0) if m else None

    @staticmethod
    def _split_sentences(text: str) -> List[str]:
        """Split text into sentences using a simple regex."""
        raw = re.split(r"(?<=[.!?;])\s+", text)
        return [s.strip() for s in raw if len(s.strip()) > 10]

    def _extract_penalty(self, sentence: str) -> Optional[str]:
        """Extract penalty language from a sentence."""
        m = re.search(
            r"(?:penalty|fine|liquidated damages?)\s*(?:of)?\s*(.+?)(?:\.|;|$)",
            sentence, re.IGNORECASE,
        )
        return m.group(1).strip() if m else None

    def _extract_nearest_date(self, sentence: str) -> Optional[str]:
        """Return the first date found in a sentence."""
        m = self._DATE_PATTERN.search(sentence)
        if m:
            return (m.group(1) or m.group(2)).strip()
        return None

    @staticmethod
    def _infer_trigger_action(sentence: str) -> str:
        """Infer the on-chain action from a trigger sentence."""
        lower = sentence.lower()
        if any(w in lower for w in ("pay", "release", "transfer", "disburse")):
            return "release_payment"
        if any(w in lower for w in ("terminate", "cancel", "void")):
            return "terminate_contract"
        if any(w in lower for w in ("notify", "alert", "inform")):
            return "emit_notification"
        if any(w in lower for w in ("penalty", "fine", "charge")):
            return "apply_penalty"
        if any(w in lower for w in ("renew", "extend")):
            return "renew_contract"
        return "custom_action"

    @staticmethod
    def _validate(parsed: ParsedContract) -> List[str]:
        """Validate that all required fields are present."""
        errors: List[str] = []
        if not parsed.parties:
            errors.append("No contracting parties could be extracted.")
        elif len(parsed.parties) < 2:
            errors.append("At least two parties are required for a valid contract.")
        if parsed.payment_terms.total_amount is None:
            errors.append("No payment amount could be extracted.")
        if not parsed.conditions:
            errors.append("No contractual conditions could be extracted.")
        if not parsed.title or parsed.title == "Untitled Contract":
            errors.append("Contract title could not be determined.")
        return errors
