// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Stablecoin.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;

    constructor(uint8 decimals_, int256 initialPrice) {
        _decimals = decimals_;
        _price = initialPrice;
    }

    function setPrice(int256 price) external {
        _price = price;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock V3 Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _price, block.timestamp, block.timestamp, 0);
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _price, block.timestamp, block.timestamp, 0);
    }
}

contract SimpleStablecoinTest is Test {
    SimpleStablecoin public stablecoin;
    MockV3Aggregator public mockPriceFeed;

    address public user1 = address(1);
    address public user2 = address(2);
    address public liquidator = address(3);

    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8; // $2000 per ETH
    uint256 public constant INITIAL_ETH_BALANCE = 100 ether;

    event VaultUpdated(address indexed user, uint256 collateral, uint256 debt);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debt, uint256 collateralSeized);

    function setUp() public {
        // Deploy mock price feed and stablecoin
        mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
        stablecoin = new SimpleStablecoin(address(mockPriceFeed));

        // Setup test accounts
        vm.deal(user1, INITIAL_ETH_BALANCE);
        vm.deal(user2, INITIAL_ETH_BALANCE);
        vm.deal(liquidator, INITIAL_ETH_BALANCE);
    }

    function test_InitialState() public view {
        assertEq(stablecoin.name(), "Simple USD");
        assertEq(stablecoin.symbol(), "sUSD");
        assertEq(address(stablecoin.priceFeed()), address(mockPriceFeed));
    }

    function test_Mint() public {
        uint256 ethToMint = 1 ether;

        // Calculate expected tokens:
        // 1 ETH = $2000
        // At 150% collateral ratio, maximum debt is:
        // (2000 * 10000) / 15000 = 1333.33...
        uint256 collateralValue = (ethToMint * uint256(INITIAL_PRICE)) / 1e8;
        uint256 expectedTokens = (collateralValue * stablecoin.RATIO_PRECISION()) / stablecoin.COLLATERAL_RATIO();

        vm.startPrank(user1);

        stablecoin.mint{value: ethToMint}();

        (uint256 collateral, uint256 debt) = stablecoin.vaults(user1);
        assertEq(collateral, ethToMint);
        assertEq(debt, expectedTokens);
        assertEq(stablecoin.balanceOf(user1), expectedTokens);

        vm.stopPrank();
    }

    function test_MultipleVaultOperations() public {
        vm.startPrank(user1);

        // Initial mint with 1 ETH
        stablecoin.mint{value: 1 ether}();
        uint256 firstMintAmount = stablecoin.balanceOf(user1);

        // Add more collateral (0.5 ETH)
        stablecoin.mint{value: 0.5 ether}();
        uint256 secondMintAmount = stablecoin.balanceOf(user1) - firstMintAmount;

        // Verify total position
        (uint256 collateral, uint256 debt) = stablecoin.vaults(user1);
        assertEq(collateral, 1.5 ether);
        assertEq(debt, firstMintAmount + secondMintAmount);

        vm.stopPrank();
    }

    function test_Liquidation() public {
        // 1. User1 creates a vault with 1 ETH at $2000 (god knows when we'll get 10k...)
        vm.startPrank(user1);
        stablecoin.mint{value: 1 ether}();
        uint256 mintedAmount = stablecoin.balanceOf(user1);
        vm.stopPrank();

        // 2. Transfer tokens to liquidator
        vm.prank(user1);
        stablecoin.transfer(liquidator, mintedAmount);

        // 3. Drop ETH price to $1500 (below liquidation threshold)
        mockPriceFeed.setPrice(1500e8);

        // 4. Check position is now liquidatable
        uint256 currentRatio = stablecoin.getCurrentRatio(user1);
        assertTrue(currentRatio < stablecoin.LIQUIDATION_THRESHOLD());

        // 5. Liquidator performs liquidation
        vm.startPrank(liquidator);
        stablecoin.liquidate(user1);

        // 6. Verify liquidation results
        (uint256 collateral, uint256 debt) = stablecoin.vaults(user1);
        assertEq(debt, 0, "Debt should be zero after liquidation");
        assertEq(collateral, 0, "Collateral should be zero after liquidation");
        vm.stopPrank();
    }

    function test_FullRepayment() public {
        // Setup: Create vault and mint tokens
        vm.startPrank(user1);
        stablecoin.mint{value: 1 ether}();
        uint256 initialDebt = stablecoin.balanceOf(user1);

        // Repay full debt
        stablecoin.repay(initialDebt);

        // Verify full repayment and collateral return
        (uint256 collateral, uint256 debt) = stablecoin.vaults(user1);
        assertEq(debt, 0);
        assertEq(collateral, 0);
        assertEq(stablecoin.balanceOf(user1), 0);
        vm.stopPrank();
    }

    function test_RevertWhen_MintingBelowMinCollateral() public {
        vm.startPrank(user1);
        vm.expectRevert("Below min collateral");
        stablecoin.mint{value: 0.09 ether}();
        vm.stopPrank();
    }

    function test_LiquidationPrice() public {
        vm.startPrank(user1);

        // Create position with 1 ETH at $2000
        stablecoin.mint{value: 1 ether}();
        (uint256 collateral, uint256 debt) = stablecoin.vaults(user1);

        // Calculate liquidation price
        uint256 liquidationPrice =
            (debt * stablecoin.LIQUIDATION_THRESHOLD() * 1e8) / (collateral * stablecoin.RATIO_PRECISION());

        // Transfer tokens to liquidator for liquidation
        vm.stopPrank();
        vm.prank(user1);
        stablecoin.transfer(liquidator, debt);

        // Price just above liquidation - should fail
        mockPriceFeed.setPrice(int256(liquidationPrice + 1e8));
        vm.prank(liquidator);
        vm.expectRevert("Position not liquidatable");
        stablecoin.liquidate(user1);

        // Price below liquidation - should succeed
        mockPriceFeed.setPrice(int256(liquidationPrice - 1e8));
        vm.prank(liquidator);
        stablecoin.liquidate(user1);
    }

    function test_PartialRepayment() public {
        // Setup: Create vault and mint tokens
        vm.startPrank(user1);
        stablecoin.mint{value: 1 ether}();
        uint256 initialDebt = stablecoin.balanceOf(user1);

        // Repay half the debt
        uint256 repayAmount = initialDebt / 2;
        stablecoin.repay(repayAmount);

        // Verify partial repayment
        (uint256 collateral, uint256 debt) = stablecoin.vaults(user1);
        assertEq(debt, initialDebt - repayAmount);
        assertEq(collateral, 1 ether); // Collateral should remain unchanged
        vm.stopPrank();
    }
}
