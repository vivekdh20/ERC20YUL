// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ─────────────────────────────────────────────────────────────────────────────
// FOUNDRY TEST IMPORTS
//
// forge-std is Foundry's standard library. It ships with every `forge init`.
// It lives at lib/forge-std/ in your project.
//
//   Test   → base contract every Foundry test must inherit from
//   console → console.log() style debugging (prints during `forge test -vv`)
//   stdError → pre-built error selectors (arithmetic overflow, etc.)
// ─────────────────────────────────────────────────────────────────────────────
import "forge-std/Test.sol";
import "../src/YulERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
// INTERFACE
//
// Our contract has NO Solidity function declarations — it uses a fallback.
// Foundry needs to know what functions exist to encode calldata correctly.
// We declare an interface so the compiler can generate the right call encoding.
//
// When you call token.transfer(bob, 100), Solidity:
//   1. Looks up transfer(address,uint256) in the interface
//   2. Computes selector: bytes4(keccak256("transfer(address,uint256)"))
//   3. ABI-encodes the arguments
//   4. Sends the encoded calldata to the contract's fallback()
// ─────────────────────────────────────────────────────────────────────────────
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function name() external view returns (bytes32);
    function symbol() external view returns (bytes32);
    function decimals() external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// ─────────────────────────────────────────────────────────────────────────────
// THE TEST CONTRACT
//
// Inheriting `Test` gives us:
//   assertEq, assertTrue, assertFalse  → assertions that revert on failure
//   vm.prank(addr)                     → next call comes FROM addr
//   vm.expectRevert()                  → assert next call reverts
//   vm.expectEmit(...)                 → assert next call emits a specific event
//   deal(addr, amount)                 → give addr some ETH
//   makeAddr("name")                   → deterministic test address from a label
// ─────────────────────────────────────────────────────────────────────────────
contract YulERC20Test is Test {

    // ─────────────────────────────────────────────────────────────────────────
    // STATE VARIABLES
    //
    // These live in THIS test contract's storage, not YulERC20's storage.
    // Each test function gets a fresh EVM state (Foundry resets between tests).
    // ─────────────────────────────────────────────────────────────────────────
    IERC20 public token;

    // Named test addresses — makeAddr() is deterministic:
    //   makeAddr("alice") always returns the same address across runs
    //   This makes test output readable ("alice" instead of 0xABCD...)
    address public alice;
    address public bob;
    address public carol;

    // Token parameters
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 1e18;  // 1 million tokens
    uint8   constant DECIMALS       = 18;
    string  constant NAME           = "YulToken";
    string  constant SYMBOL         = "YUL";

    // ─────────────────────────────────────────────────────────────────────────
    // setUp()
    //
    // Foundry calls setUp() before EVERY test function.
    // This is where you deploy contracts and set up initial state.
    //
    // Equivalent to Hardhat's beforeEach().
    // ─────────────────────────────────────────────────────────────────────────
    function setUp() public {
        // makeAddr generates a deterministic address from a string label.
        // Under the hood: address(uint160(uint256(keccak256("alice"))))
        alice = makeAddr("alice");
        bob   = makeAddr("bob");
        carol = makeAddr("carol");

        // Deploy YulERC20. The deployer is address(this) — the test contract.
        // Constructor mints INITIAL_SUPPLY to msg.sender (= address(this)).
        YulERC20 deployed = new YulERC20(NAME, SYMBOL, DECIMALS, INITIAL_SUPPLY);

        // Wrap in our interface so calls get proper ABI encoding
        token = IERC20(address(deployed));
    }

    // =========================================================================
    // SECTION 1: DEPLOYMENT & INITIAL STATE
    //
    // Verify the constructor stored everything correctly.
    // This teaches you: storage slots, how bytes32 name/symbol works.
    // =========================================================================

    function test_InitialSupply() public view {
        // totalSupply() reads slot 0 in YulERC20 and returns it.
        // assertEq(a, b) reverts with a readable diff if a != b.
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_DeployerReceivesInitialSupply() public view {
        // address(this) is the test contract — it deployed YulERC20.
        // balanceOf() computes keccak256(address(this) ++ slot1) and reads it.
        assertEq(token.balanceOf(address(this)), INITIAL_SUPPLY);
    }

    function test_DecimaIs18() public view {
        assertEq(token.decimals(), 18);
    }

    function test_NameStoredCorrectly() public view {
        // Our Yul stores name as bytes32 (mload(add(_name, 32))).
        // This reads the first 32 bytes of the string — fine for short names.
        // "YulToken" fits in 32 bytes, so this works perfectly.
        bytes32 expected = bytes32(bytes(NAME));  // left-pads with zeros
        assertEq(token.name(), expected);
    }

    function test_SymbolStoredCorrectly() public view {
        bytes32 expected = bytes32(bytes(SYMBOL));
        assertEq(token.symbol(), expected);
    }

    function test_InitialBalanceIsZeroForArbitraryAddress() public view {
        // Slots that were never written read as 0 — this is an EVM guarantee.
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    // =========================================================================
    // SECTION 2: TRANSFER
    //
    // Teaches: vm.prank, event assertions, balance accounting
    // =========================================================================

    function test_TransferUpdatesBalances() public {
        uint256 amount = 500 * 1e18;

        // address(this) currently holds all tokens. Transfer to alice.
        // No prank needed — `this` is the default caller.
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice),        amount);
        assertEq(token.balanceOf(address(this)), INITIAL_SUPPLY - amount);
    }

    function test_TransferEmitsEvent() public {
        uint256 amount = 100 * 1e18;

        // ── vm.expectEmit ───────────────────────────────────────────────────
        // Parameters: (checkTopic1, checkTopic2, checkTopic3, checkData)
        //   topic1 = `from` (indexed)
        //   topic2 = `to`   (indexed)
        //   data   = amount (non-indexed)
        //
        // You must call expectEmit, THEN emit the reference event,
        // THEN call the function that should emit it.
        //
        // Foundry records the reference event and compares it against the
        // actual event emitted by the next external call.
        // ────────────────────────────────────────────────────────────────────
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, amount);

        token.transfer(alice, amount);
    }

    function test_TransferReturnTrue() public {
        // ERC-20 standard: transfer() must return bool true on success.
        // Our Yul does: mstore(0x00, 1); return(0x00, 0x20)
        bool result = token.transfer(alice, 1);
        assertTrue(result);
    }

    function test_TransferBetweenNonDeployerAccounts() public {
        // First give alice some tokens
        token.transfer(alice, 1000 * 1e18);

        // vm.prank(addr): the NEXT call is made as if msg.sender == addr
        // Only affects one call. After that, msg.sender reverts to address(this).
        vm.prank(alice);
        token.transfer(bob, 400 * 1e18);

        assertEq(token.balanceOf(alice), 600 * 1e18);
        assertEq(token.balanceOf(bob),   400 * 1e18);
    }

    // ── REVERT TESTS ─────────────────────────────────────────────────────────
    // vm.expectRevert() asserts that the NEXT external call reverts.
    // Our Yul uses bare `revert(0, 0)` — no error data — so we pass no args.
    // ─────────────────────────────────────────────────────────────────────────

    function test_TransferRevertsIfInsufficientBalance() public {
        // alice has 0 tokens. Trying to send any amount should revert.
        vm.expectRevert();
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_TransferRevertsIfToIsZeroAddress() public {
        // Our Yul checks: if iszero(to) { revert(0, 0) }
        vm.expectRevert();
        token.transfer(address(0), 100);
    }

    function test_TransferDoesNotExceedBalance() public {
        uint256 balance = token.balanceOf(address(this));

        // Transferring exactly the balance should succeed
        token.transfer(alice, balance);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), balance);
    }

    function test_TransferOneMoreThanBalanceReverts() public {
        uint256 balance = token.balanceOf(address(this));

        vm.expectRevert();
        token.transfer(alice, balance + 1);
    }

    // =========================================================================
    // SECTION 3: APPROVE & ALLOWANCE
    //
    // Teaches: nested mapping slot derivation, event topics
    // =========================================================================

    function test_ApproveSetAllowance() public {
        uint256 amount = 200 * 1e18;

        // address(this) approves alice to spend `amount`
        token.approve(alice, amount);

        // allowance() reads: keccak256(spender ++ keccak256(owner ++ slot2))
        assertEq(token.allowance(address(this), alice), amount);
    }

    function test_ApproveEmitsEvent() public {
        uint256 amount = 50 * 1e18;

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), alice, amount);

        token.approve(alice, amount);
    }

    function test_ApproveReturnsTrue() public {
        assertTrue(token.approve(alice, 100));
    }

    function test_AllowanceIsZeroByDefault() public view {
        // No approval has been set — storage slot is 0 by default
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_ApproveOverwritesPreviousAllowance() public {
        token.approve(alice, 1000);
        token.approve(alice, 500);   // overwrite — no addition, just sstore
        assertEq(token.allowance(address(this), alice), 500);
    }

    function test_ApproveZeroRevokesAllowance() public {
        token.approve(alice, 1000);
        token.approve(alice, 0);
        assertEq(token.allowance(address(this), alice), 0);
    }

    function test_AllowancesAreIndependent() public {
        // alice and bob can both be approved independently by the same owner
        token.approve(alice, 100);
        token.approve(bob,   200);

        assertEq(token.allowance(address(this), alice), 100);
        assertEq(token.allowance(address(this), bob),   200);
    }

    // =========================================================================
    // SECTION 4: TRANSFER FROM
    //
    // Teaches: multi-step flows, allowance deduction, max uint256 trick
    // =========================================================================

    function test_TransferFromBasicFlow() public {
        uint256 amount = 300 * 1e18;

        // Step 1: owner (this) approves alice
        token.approve(alice, amount);

        // Step 2: alice transfers FROM owner TO bob
        vm.prank(alice);
        token.transferFrom(address(this), bob, amount);

        assertEq(token.balanceOf(bob),           amount);
        assertEq(token.balanceOf(address(this)), INITIAL_SUPPLY - amount);
    }

    function test_TransferFromDeductsAllowance() public {
        token.approve(alice, 1000 * 1e18);

        vm.prank(alice);
        token.transferFrom(address(this), bob, 400 * 1e18);

        // Allowance should be reduced by 400
        assertEq(token.allowance(address(this), alice), 600 * 1e18);
    }

    function test_TransferFromEmitsTransferEvent() public {
        uint256 amount = 100 * 1e18;
        token.approve(alice, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), bob, amount);

        vm.prank(alice);
        token.transferFrom(address(this), bob, amount);
    }

    function test_TransferFromRevertsIfAllowanceInsufficient() public {
        token.approve(alice, 50 * 1e18);

        vm.expectRevert();
        vm.prank(alice);
        token.transferFrom(address(this), bob, 100 * 1e18);  // 100 > 50
    }

    function test_TransferFromRevertsIfBalanceInsufficient() public {
        // Give alice a huge allowance, but the owner has no tokens
        vm.prank(alice);
        // alice has 0 tokens, approves bob for infinite
        token.approve(bob, type(uint256).max);

        vm.expectRevert();
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);  // alice has 0 balance
    }

    function test_TransferFromRevertsIfToIsZero() public {
        token.approve(alice, 100);

        vm.expectRevert();
        vm.prank(alice);
        token.transferFrom(address(this), address(0), 100);
    }

    function test_TransferFromWithMaxUint256AllowanceDoesNotDeduct() public {
        // ── The max-allowance pattern ────────────────────────────────────────
        // Many protocols use type(uint256).max as "infinite" allowance.
        // Our Yul handles this with:
        //   let maxUint := not(0)               // all bits set = 2^256 - 1
        //   if iszero(eq(allAmt, maxUint)) {    // if NOT max, deduct
        //       sstore(allSlot, sub(allAmt, amount))
        //   }
        // This saves an SSTORE on each transferFrom when max is approved.
        // ────────────────────────────────────────────────────────────────────
        token.approve(alice, type(uint256).max);

        vm.prank(alice);
        token.transferFrom(address(this), bob, 500 * 1e18);

        // Allowance should still be max — no deduction happened
        assertEq(token.allowance(address(this), alice), type(uint256).max);
    }

    function test_TransferFromReturnsTrue() public {
        token.approve(alice, 100);

        vm.prank(alice);
        bool result = token.transferFrom(address(this), bob, 100);
        assertTrue(result);
    }

    // =========================================================================
    // SECTION 5: TOTAL SUPPLY INVARIANT
    //
    // Teaches: invariant thinking — tokens should never be created or destroyed
    // =========================================================================

    function test_TotalSupplyNeverChanges() public {
        // Transfer does NOT change totalSupply — tokens move, they don't vanish
        token.transfer(alice, 100 * 1e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);

        // Approve + transferFrom also doesn't change totalSupply
        token.approve(alice, 500 * 1e18);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 500 * 1e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_SumOfBalancesEqualsSupply() public {
        // Distribute tokens to everyone
        token.transfer(alice, 300_000 * 1e18);
        token.transfer(bob,   200_000 * 1e18);
        // address(this) retains the rest: 500_000

        uint256 sum =
            token.balanceOf(address(this)) +
            token.balanceOf(alice) +
            token.balanceOf(bob);

        assertEq(sum, token.totalSupply());
    }

    // =========================================================================
    // SECTION 6: EDGE CASES & SELF-TRANSFERS
    //
    // These catch subtle bugs that are easy to miss in production contracts
    // =========================================================================

    function test_TransferToSelf() public {
        uint256 balBefore = token.balanceOf(address(this));

        // Sending to yourself: from == to
        // Our Yul does:
        //   fromBal -= amount  → 1_000_000e18 - 100 = 999_999...900
        //   toBal   += amount  → 999_999...900 + 100 = back to 1_000_000e18
        // (Because fromSlot == toSlot, the second sstore overwrites the first!)
        //
        // NOTE: This is a subtle behavior — the net result is correct but
        // internally the first sstore is wasted. Most ERC-20s have this quirk.
        token.transfer(address(this), 100);

        assertEq(token.balanceOf(address(this)), balBefore);
    }

    function test_TransferZeroAmount() public {
        // Transferring 0 should not revert — it's a valid ERC-20 operation
        // from balance: 1_000_000e18 - 0 = 1_000_000e18 ✓
        // to balance:   0 + 0 = 0 ✓
        // overflow check: 0 >= 0 ✓
        token.transfer(alice, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_MultipleTransfersAccumulate() public {
        token.transfer(alice, 100 * 1e18);
        token.transfer(alice, 200 * 1e18);
        token.transfer(alice, 300 * 1e18);

        assertEq(token.balanceOf(alice), 600 * 1e18);
    }

    // =========================================================================
    // SECTION 7: FUZZ TESTING
    //
    // Foundry automatically runs fuzz tests hundreds of times with random inputs.
    // The `amount` parameter below is randomly generated each run.
    //
    // Run with: forge test --match-test testFuzz -vv
    // Or set runs in foundry.toml: [fuzz] runs = 1000
    // =========================================================================

    function testFuzz_TransferAmount(uint256 amount) public {
        // vm.assume() discards inputs that violate our preconditions.
        // If a generated value doesn't pass assume(), Foundry tries another.
        vm.assume(amount <= INITIAL_SUPPLY);
        vm.assume(amount > 0);

        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice),        amount);
        assertEq(token.balanceOf(address(this)), INITIAL_SUPPLY - amount);
        // Invariant: total never changes
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function testFuzz_ApproveAndTransferFrom(uint256 amount) public {
        vm.assume(amount <= INITIAL_SUPPLY);

        token.approve(alice, amount);

        vm.prank(alice);
        token.transferFrom(address(this), bob, amount);

        assertEq(token.balanceOf(bob), amount);
    }

    // =========================================================================
    // SECTION 8: STORAGE LAYOUT VERIFICATION (advanced)
    //
    // We manually read raw storage slots to verify our Yul layout is correct.
    // vm.load(addr, slot) is a Foundry cheatcode that reads raw storage.
    //
    // This is the most direct proof that your slot derivation is correct.
    // =========================================================================

    function test_RawStorageSlot0IsTotalSupply() public view {
        // slot 0 = totalSupply
        bytes32 raw = vm.load(address(token), bytes32(uint256(0)));
        assertEq(uint256(raw), INITIAL_SUPPLY);
    }

    function test_RawStorageSlot5IsDecimals() public view {
        // slot 5 = decimals
        bytes32 raw = vm.load(address(token), bytes32(uint256(5)));
        assertEq(uint256(raw), DECIMALS);
    }

    function test_RawBalanceSlotMatchesBalanceOf() public view {
        // Manually compute the storage slot for balanceOf[address(this)]
        // This mirrors what our Yul does in balanceSlot():
        //   keccak256(address(this) ++ slot1)
        bytes32 slot = keccak256(abi.encode(address(this), uint256(1)));
        bytes32 raw  = vm.load(address(token), slot);

        assertEq(uint256(raw), token.balanceOf(address(this)));
    }

    function test_RawAllowanceSlotMatchesAllowance() public {
        uint256 amount = 777 * 1e18;
        token.approve(alice, amount);

        // Manually compute allowance[address(this)][alice]:
        //   inner = keccak256(owner  ++ slot2)
        //   slot  = keccak256(spender ++ inner)
        bytes32 inner = keccak256(abi.encode(address(this), uint256(2)));
        bytes32 slot  = keccak256(abi.encode(alice, inner));
        bytes32 raw   = vm.load(address(token), slot);

        assertEq(uint256(raw), amount);
    }

    // =========================================================================
    // SECTION 9: CALLDATA ANATOMY (manual low-level calls)
    //
    // Here we bypass the interface and call the contract with raw calldata.
    // This teaches you exactly what the ABI encodes on every call.
    //
    // Calldata layout for transfer(address to, uint256 amount):
    //   bytes  0- 3: selector (4 bytes)  = keccak256("transfer(address,uint256)")[0:4]
    //   bytes  4-35: to       (32 bytes) = address, left-padded with 12 zero bytes
    //   bytes 36-67: amount   (32 bytes) = uint256, big-endian
    // =========================================================================

    function test_RawCalldataTransfer() public {
        uint256 amount  = 123 * 1e18;
        bytes4  selector = bytes4(keccak256("transfer(address,uint256)"));

        // abi.encodeWithSelector does exactly what Solidity does normally
        bytes memory data = abi.encodeWithSelector(selector, alice, amount);

        // Low-level call — returns (success, returnData)
        (bool ok, bytes memory ret) = address(token).call(data);

        assertTrue(ok);
        // returnData is ABI-encoded bool true = 32 bytes of 0x00...01
        assertEq(abi.decode(ret, (bool)), true);
        assertEq(token.balanceOf(alice), amount);
    }

    function test_RawCalldataBalanceOf() public view {
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("balanceOf(address)")),
            address(this)
        );
        (, bytes memory ret) = address(token).staticcall(data);
        assertEq(abi.decode(ret, (uint256)), INITIAL_SUPPLY);
    }
}
