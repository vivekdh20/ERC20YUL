// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ─────────────────────────────────────────────────────────────────────────────
// GAS BENCHMARK: YulERC20 vs OpenZeppelin ERC20
//
// Strategy: every test function runs the SAME operation on both contracts
// back-to-back. forge snapshot records the gas for each test individually,
// so you get a direct line-by-line comparison in .gas-snapshot.
//
// We separate Yul tests and OZ tests into different functions so the snapshot
// file shows each contract's cost on its own line — easy to diff.
// ─────────────────────────────────────────────────────────────────────────────

import "forge-std/Test.sol";
import "../src/YulERC20.sol";
import "../src/OZToken.sol";

interface IERC20Min {
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract GasBenchmark is Test {

    IERC20Min yul;
    IERC20Min oz;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    uint256 constant SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        YulERC20 y = new YulERC20("YulToken", "YUL", 18, SUPPLY);
        OZToken  o = new OZToken ("OZToken",  "OZ",  18, SUPPLY);
        yul = IERC20Min(address(y));
        oz  = IERC20Min(address(o));
    }

    // =========================================================================
    // DEPLOYMENT
    // Deploy cost is measured separately — setUp() doesn't count toward test gas.
    // We deploy fresh instances inside these tests to capture constructor cost.
    // =========================================================================

    function test_Deploy_Yul() public {
        new YulERC20("YulToken", "YUL", 18, SUPPLY);
    }

    function test_Deploy_OZ() public {
        new OZToken("OZToken", "OZ", 18, SUPPLY);
    }

    // =========================================================================
    // TOTAL SUPPLY  (pure SLOAD — the floor cost of a read)
    // =========================================================================

    function test_TotalSupply_Yul() public view {
        yul.totalSupply();
    }

    function test_TotalSupply_OZ() public view {
        oz.totalSupply();
    }

    // =========================================================================
    // BALANCE OF
    // =========================================================================

    function test_BalanceOf_Yul() public view {
        yul.balanceOf(address(this));
    }

    function test_BalanceOf_OZ() public view {
        oz.balanceOf(address(this));
    }

    // =========================================================================
    // TRANSFER  (the core operation — 2 SLOADs + 2 SSTOREs + 1 LOG)
    // =========================================================================

    function test_Transfer_Yul() public {
        yul.transfer(alice, 1000 * 1e18);
    }

    function test_Transfer_OZ() public {
        oz.transfer(alice, 1000 * 1e18);
    }

    // Transfer when recipient already has a balance (warm SSTORE vs cold)
    function test_Transfer_WarmRecipient_Yul() public {
        yul.transfer(alice, 1);          // warm alice's slot
        yul.transfer(alice, 1000 * 1e18);
    }

    function test_Transfer_WarmRecipient_OZ() public {
        oz.transfer(alice, 1);
        oz.transfer(alice, 1000 * 1e18);
    }

    // =========================================================================
    // APPROVE
    // =========================================================================

    function test_Approve_Yul() public {
        yul.approve(alice, 500 * 1e18);
    }

    function test_Approve_OZ() public {
        oz.approve(alice, 500 * 1e18);
    }

    // =========================================================================
    // TRANSFER FROM  (most expensive: 3 SLOADs + 3 SSTOREs + 1 LOG)
    // =========================================================================

    function test_TransferFrom_Yul() public {
        yul.approve(alice, 500 * 1e18);
        vm.prank(alice);
        yul.transferFrom(address(this), bob, 500 * 1e18);
    }

    function test_TransferFrom_OZ() public {
        oz.approve(alice, 500 * 1e18);
        vm.prank(alice);
        oz.transferFrom(address(this), bob, 500 * 1e18);
    }

    // Max uint256 allowance — skips allowance SSTORE on transferFrom
    function test_TransferFrom_MaxAllowance_Yul() public {
        yul.approve(alice, type(uint256).max);
        vm.prank(alice);
        yul.transferFrom(address(this), bob, 500 * 1e18);
    }

    function test_TransferFrom_MaxAllowance_OZ() public {
        oz.approve(alice, type(uint256).max);
        vm.prank(alice);
        oz.transferFrom(address(this), bob, 500 * 1e18);
    }

    // =========================================================================
    // ALLOWANCE READ
    // =========================================================================

    function test_Allowance_Yul() public {
        yul.approve(alice, 100);
        yul.allowance(address(this), alice);
    }

    function test_Allowance_OZ() public {
        oz.approve(alice, 100);
        oz.allowance(address(this), alice);
    }
}