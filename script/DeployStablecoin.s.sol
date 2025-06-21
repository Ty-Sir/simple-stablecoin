// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/Stablecoin.sol";

contract DeployStablecoin is Script {
    function run() external {
        // Sepolia ETH/USD Price Feed
        address priceFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

        // Start broadcasting transactions
        vm.broadcast();

        // Deploy the contract
        SimpleStablecoin stablecoin = new SimpleStablecoin(priceFeedAddress);

        console.log("Stablecoin deployed to:", address(stablecoin));
        console.log("Price Feed Address:", priceFeedAddress);
    }
}
