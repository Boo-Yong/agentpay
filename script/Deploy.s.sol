// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AgentPay} from "../src/AgentPay.sol";

/// @notice Deploy AgentPay to QDay Aevum Testnet (chain ID 44005).
/// @dev Usage:
///      TUSD8=0x456569838f1d43009A91ebA4263147Afd7233483 \
///      forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info \
///        --private-key $PRIVATE_KEY --broadcast
///      Verify afterwards:
///      forge verify-contract <ADDRESS> src/AgentPay.sol:AgentPay \
///        --chain-id 44005 --verifier blockscout \
///        --verifier-url https://explorer-test.qday.info/api \
///        --constructor-args $(cast abi-encode "constructor(address)" $TUSD8)
contract Deploy is Script {
    function run() external {
        address tusd8 = vm.envAddress("TUSD8");
        vm.startBroadcast();
        AgentPay agentPay = new AgentPay(tusd8);
        vm.stopBroadcast();
        console.log("AgentPay deployed at:", address(agentPay));
        console.log("tUSD8:", tusd8);
    }
}
