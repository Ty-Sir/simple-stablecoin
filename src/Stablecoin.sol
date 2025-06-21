// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract SimpleStablecoin is ERC20, ReentrancyGuard {
    AggregatorV3Interface public priceFeed;

    uint256 public constant COLLATERAL_RATIO = 15000; // 150%
    uint256 public constant RATIO_PRECISION = 10000; // 100%
    uint256 public constant MIN_COLLATERAL = 0.1 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 13000; // 130%

    struct Vault {
        uint256 collateralAmount;
        uint256 debtAmount;
    }

    mapping(address => Vault) public vaults;

    event VaultUpdated(address indexed user, uint256 collateral, uint256 debt);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debt, uint256 collateralSeized);

    constructor(address _priceFeed) ERC20("Simple USD", "sUSD") {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    // Get ETH/USD price from Chainlink
    function getEthPrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    // Mint stablecoins by depositing ETH
    function mint() external payable nonReentrant {
        require(msg.value >= MIN_COLLATERAL, "Below min collateral");

        Vault storage vault = vaults[msg.sender];
        uint256 ethPrice = getEthPrice();

        uint256 newCollateral = vault.collateralAmount + msg.value;
        uint256 collateralValue = (newCollateral * ethPrice) / 1e8;
        uint256 maxSafeDebt = (collateralValue * RATIO_PRECISION) / COLLATERAL_RATIO;

        uint256 additionalDebt = maxSafeDebt;
        if (vault.debtAmount > 0) {
            require(maxSafeDebt > vault.debtAmount, "No additional debt available");
            additionalDebt = maxSafeDebt - vault.debtAmount;
        }

        vault.collateralAmount = newCollateral;
        vault.debtAmount += additionalDebt;

        _mint(msg.sender, additionalDebt);

        emit VaultUpdated(msg.sender, newCollateral, vault.debtAmount);
    }

    // Repay stablecoin debt
    function repay(uint256 amount) external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        require(vault.debtAmount >= amount, "Repaying too much");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        vault.debtAmount -= amount;

        if (vault.debtAmount == 0) {
            uint256 collateralToReturn = vault.collateralAmount;
            vault.collateralAmount = 0;
            (bool success,) = msg.sender.call{value: collateralToReturn}("");
            require(success, "ETH transfer failed");
        }

        emit VaultUpdated(msg.sender, vault.collateralAmount, vault.debtAmount);
    }

    // Liquidate users that are undercollateralized
    function liquidate(address user) external nonReentrant {
        Vault storage vault = vaults[user];
        require(vault.debtAmount > 0, "No debt to liquidate");
        require(getCurrentRatio(user) < LIQUIDATION_THRESHOLD, "Position not liquidatable");

        uint256 debtToRepay = vault.debtAmount;
        require(balanceOf(msg.sender) >= debtToRepay, "Insufficient balance to liquidate");

        uint256 ethPrice = getEthPrice();
        uint256 collateralToSeize = (debtToRepay * 1e8) / ethPrice;

        require(collateralToSeize <= vault.collateralAmount, "Not enough collateral");

        vault.collateralAmount = 0;
        vault.debtAmount = 0;

        _burn(msg.sender, debtToRepay);

        (bool success,) = msg.sender.call{value: collateralToSeize}("");
        require(success, "ETH transfer failed");

        emit Liquidated(user, msg.sender, debtToRepay, collateralToSeize);
        emit VaultUpdated(user, 0, 0);
    }

    // Get Current Ratio of Collateralization
    function getCurrentRatio(address user) public view returns (uint256) {
        Vault storage vault = vaults[user];
        if (vault.debtAmount == 0) return type(uint256).max;

        uint256 ethPrice = getEthPrice();
        uint256 collateralValue = (vault.collateralAmount * ethPrice) / 1e8;
        return (collateralValue * RATIO_PRECISION) / vault.debtAmount;
    }
}
