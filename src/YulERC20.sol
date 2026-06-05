// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title YulERC20
/// @notice A fully ERC-20 compliant token written in inline Yul assembly.
/// @dev No OpenZeppelin. No Solidity logic. Pure opcodes.
contract YulERC20 {
    // -------------------------------------------------------------------------
    // STORAGE LAYOUT  (we define this — the compiler doesn't)
    // slot 0 → totalSupply (uint256)
    // slot 1 → balanceOf   mapping(address => uint256)
    // slot 2 → allowance   mapping(address => mapping(address => uint256))
    // slot 3 → name        (we store as bytes32 for simplicity)
    // slot 4 → symbol      (bytes32)
    // slot 5 → decimals    (uint8, stored as uint256)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // EVENTS (declared in Solidity so the ABI knows about them,
    //         but we emit them manually in Yul)
    // -------------------------------------------------------------------------
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // -------------------------------------------------------------------------
    // CONSTRUCTOR — runs in Solidity, sets up initial state
    // -------------------------------------------------------------------------
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) {
        assembly {
            // store name as bytes32 (truncated/padded) at slot 3
            sstore(3, mload(add(_name, 32)))
            // store symbol at slot 4
            sstore(4, mload(add(_symbol, 32)))
            // store decimals at slot 5
            sstore(5, _decimals)

            // totalSupply = _initialSupply  (slot 0)
            sstore(0, _initialSupply)

            // balanceOf[msg.sender] = _initialSupply
            // key = keccak256(msg.sender ++ slot1)
            let ptr := mload(0x40)          // free memory pointer
            mstore(ptr, caller())           // store msg.sender at ptr
            mstore(add(ptr, 0x20), 1)       // store slot number (1) after it
            let balSlot := keccak256(ptr, 0x40)  // hash 64 bytes
            sstore(balSlot, _initialSupply)

            // emit Transfer(address(0), msg.sender, _initialSupply)
            // Transfer topic = keccak256("Transfer(address,indexed,uint256)")
            mstore(ptr, _initialSupply)     // data = amount
            log3(
                ptr, 0x20,                  // data: 32 bytes (the amount)
                // topic0: event signature
                0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                0,                          // topic1: from = address(0)
                caller()                    // topic2: to = msg.sender
            )
        }
    }

    // -------------------------------------------------------------------------
    // FALLBACK — all external calls land here, we route them manually
    // -------------------------------------------------------------------------
    fallback() external {
        assembly {
            // Read the 4-byte function selector from calldata
            // calldataload(0) loads 32 bytes starting at byte 0
            // We shift right by 28 bytes (224 bits) to get just the first 4 bytes
            let selector := shr(224, calldataload(0))

            // ── ROUTER ──────────────────────────────────────────────────────
            // Compare selector against known function signatures and jump

            // totalSupply()          → 0x18160ddd
            if eq(selector, 0x18160ddd) { _totalSupply() }

            // balanceOf(address)     → 0x70a08231
            if eq(selector, 0x70a08231) { _balanceOf() }

            // transfer(address,uint256) → 0xa9059cbb
            if eq(selector, 0xa9059cbb) { _transfer() }

            // approve(address,uint256)  → 0x095ea7b3
            if eq(selector, 0x095ea7b3) { _approve() }

            // allowance(address,address) → 0xdd62ed3e
            if eq(selector, 0xdd62ed3e) { _allowance() }

            // transferFrom(address,address,uint256) → 0x23b872dd
            if eq(selector, 0x23b872dd) { _transferFrom() }

            // name()    → 0x06fdde03
            if eq(selector, 0x06fdde03) { _name() }

            // symbol()  → 0x95d89b41
            if eq(selector, 0x95d89b41) { _symbol() }

            // decimals() → 0x313ce567
            if eq(selector, 0x313ce567) { _decimals() }

            // ── HELPER FUNCTIONS ─────────────────────────────────────────────
            // Yul functions defined inside assembly block

            function _totalSupply() {
                // load slot 0 and return it
                mstore(0x00, sload(0))
                return(0x00, 0x20)
            }

            function _name() {
                mstore(0x00, sload(3))
                return(0x00, 0x20)
            }

            function _symbol() {
                mstore(0x00, sload(4))
                return(0x00, 0x20)
            }

            function _decimals() {
                mstore(0x00, sload(5))
                return(0x00, 0x20)
            }

            function _balanceOf() {
                // calldataload(4) → the address argument (padded to 32 bytes)
                let account := calldataload(4)
                mstore(0x00, sload(balanceSlot(account)))
                return(0x00, 0x20)
            }

            function _allowance() {
                let owner   := calldataload(4)
                let spender := calldataload(36)
                mstore(0x00, sload(allowanceSlot(owner, spender)))
                return(0x00, 0x20)
            }

            function _approve() {
                let owner   := caller()
                let spender := calldataload(4)
                let amount  := calldataload(36)

                sstore(allowanceSlot(owner, spender), amount)

                // emit Approval(owner, spender, amount)
                mstore(0x00, amount)
                log3(
                    0x00, 0x20,
                    0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925,
                    owner,
                    spender
                )
                // return true (1)
                mstore(0x00, 1)
                return(0x00, 0x20)
            }

            function _transfer() {
                let from   := caller()
                let to     := calldataload(4)
                let amount := calldataload(36)

                // Validate: to != address(0)
                if iszero(to) { revert(0, 0) }

                let fromSlot := balanceSlot(from)
                let fromBal  := sload(fromSlot)

                // Validate: sufficient balance
                if lt(fromBal, amount) { revert(0, 0) }

                // from balance -= amount
                sstore(fromSlot, sub(fromBal, amount))

                // to balance += amount  (check overflow)
                let toSlot := balanceSlot(to)
                let toBal  := sload(toSlot)
                let newToBal := add(toBal, amount)
                if lt(newToBal, toBal) { revert(0, 0) }  // overflow check
                sstore(toSlot, newToBal)

                // emit Transfer(from, to, amount)
                mstore(0x00, amount)
                log3(
                    0x00, 0x20,
                    0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                    from,
                    to
                )

                mstore(0x00, 1)
                return(0x00, 0x20)
            }

            function _transferFrom() {
                let from    := calldataload(4)
                let to      := calldataload(36)
                let amount  := calldataload(68)

                if iszero(to) { revert(0, 0) }

                // Check and decrease allowance
                let allSlot := allowanceSlot(from, caller())
                let allAmt  := sload(allSlot)

                // If allowance is not max uint256, deduct it
                let maxUint := not(0)
                if iszero(eq(allAmt, maxUint)) {
                    if lt(allAmt, amount) { revert(0, 0) }
                    sstore(allSlot, sub(allAmt, amount))
                }

                // Deduct from sender
                let fromSlot := balanceSlot(from)
                let fromBal  := sload(fromSlot)
                if lt(fromBal, amount) { revert(0, 0) }
                sstore(fromSlot, sub(fromBal, amount))

                // Credit to recipient
                let toSlot  := balanceSlot(to)
                let toBal   := sload(toSlot)
                let newToBal := add(toBal, amount)
                if lt(newToBal, toBal) { revert(0, 0) }
                sstore(toSlot, newToBal)

                // emit Transfer(from, to, amount)
                mstore(0x00, amount)
                log3(
                    0x00, 0x20,
                    0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                    from,
                    to
                )

                mstore(0x00, 1)
                return(0x00, 0x20)
            }

            // ── STORAGE KEY HELPERS ──────────────────────────────────────────

            /// @dev Compute storage slot for balanceOf[account]
            ///      slot = keccak256(account ++ 1)
            function balanceSlot(account) -> slot {
                mstore(0x00, account)
                mstore(0x20, 1)           // mapping is at slot 1
                slot := keccak256(0x00, 0x40)
            }

            /// @dev Compute storage slot for allowance[owner][spender]
            ///      First hash: inner = keccak256(owner ++ 2)
            ///      Then:       slot  = keccak256(spender ++ inner)
            function allowanceSlot(owner, spender) -> slot {
                mstore(0x00, owner)
                mstore(0x20, 2)           // outer mapping at slot 2
                let inner := keccak256(0x00, 0x40)
                mstore(0x00, spender)
                mstore(0x20, inner)
                slot := keccak256(0x00, 0x40)
            }
        }
    }
}