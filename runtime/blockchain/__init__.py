"""
MTRX Blockchain Runtime — service layer for all 30 on-chain components.

Each sub-package in `services/` maps 1:1 to a Solidity contract in `contracts/`.
Services provide Python business logic, state tracking, and Web3 transaction
building without requiring a live chain connection (all blockchain calls are
injectable).
"""
