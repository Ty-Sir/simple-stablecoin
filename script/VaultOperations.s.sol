// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Stablecoin.sol";

contract VaultOperations is Script {
    SimpleStablecoin stablecoin;
    address constant STABLECOIN_ADDRESS =
        0x8734D6f16e59F14973fB5170E0C9A1d511ea1aD1;

    function setUp() public {
        stablecoin = SimpleStablecoin(payable(STABLECOIN_ADDRESS));
    }

    function createAndMint() public {
        vm.broadcast();

        // Mint directly with collateral (vault creation is handled in mint function)
        uint256 collateralAmount = 0.1 ether;
        stablecoin.mint{value: collateralAmount}();

        // Log results
        (uint256 collateral, uint256 debt) = stablecoin.vaults(msg.sender);
        console.log("Created vault with", collateralAmount, "ETH");
        console.log("Current collateral:", collateral);
        console.log("Current debt:", debt);
        console.log("Current ratio:", stablecoin.getCurrentRatio(msg.sender));
    }

    function repayAndWithdraw(uint256 amount) public {
        (uint256 collateral, uint256 debt) = stablecoin.vaults(msg.sender);
        require(debt > 0, "No debt to repay");
        require(amount <= debt, "Amount exceeds debt");

        vm.broadcast();
        stablecoin.repay(amount);

        // Log results
        (uint256 newCollateral, uint256 newDebt) = stablecoin.vaults(
            msg.sender
        );
        console.log("Repaid", amount, "tokens");
        console.log("Collateral returned:", collateral - newCollateral);
        console.log("Remaining debt:", newDebt);
    }

    function checkLiquidation(address user) public view {
        (uint256 collateral, uint256 debt) = stablecoin.vaults(user);
        if (debt == 0) {
            console.log("No active vault for user");
            return;
        }

        uint256 currentRatio = stablecoin.getCurrentRatio(user);
        uint256 liquidationThreshold = stablecoin.LIQUIDATION_THRESHOLD();

        console.log("Current collateral:", collateral);
        console.log("Current debt:", debt);
        console.log("Current ratio:", currentRatio);
        console.log("Liquidation threshold:", liquidationThreshold);
        console.log("Liquidatable:", currentRatio < liquidationThreshold);
    }

    function liquidatePosition(address user) public {
        require(
            stablecoin.getCurrentRatio(user) <
                stablecoin.LIQUIDATION_THRESHOLD(),
            "Position not liquidatable"
        );

        (uint256 collateral, uint256 debt) = stablecoin.vaults(user);
        console.log(
            "Attempting to liquidate position with %d collateral and %d debt",
            collateral,
            debt
        );

        vm.broadcast();
        stablecoin.liquidate(user);

        console.log("Position liquidated successfully");
    }
}
