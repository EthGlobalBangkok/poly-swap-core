// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LayerZeroRead} from "../contracts/LayerZeroRead.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract LayerZeroReadTest is Script {
    using OptionsBuilder for bytes;

    LayerZeroRead public lzread;

    function setUp() public {}

    function run() public {
        // bytes mescrimory deploycode = abi.encodePacked(type(SyncSafeModule).creationCode, safeProxyFactory, lzEndpoint, sender);

        // console.log(vmSafe.toString(deploycode));

        vm.broadcast();
        lzread = new LayerZeroRead(
            // 0x1a44076050125825900e736c501f859c50fE728c, // arbitrum mainnet from here: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
            0x6EDCE65403992e310A62460808c4b910D972f10f, // arbitrum sepolia from here: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
            msg.sender,
            "poly-swap-core"
        );
        vm.broadcast();

        // uint32 channelId = 4294967295; // mainnet
        uint32 channelId = 4294967295; // sepolia

        lzread.setPeer(channelId, bytes32(uint256(uint160(address(lzread)))));
        vm.broadcast();

        uint128 _value = 0.00015 ether;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReadOption(500000, 500, 0);

        lzread.send{value: _value}(
            channelId, // channel ID
            1, // app label
            options,
            // 30109, // mainnet
            40245, // sepolia
            0x190c4029e6206c1c3373571cb74b6e772da865b52755089e9d9d2fff9bb51811
        );
        vm.broadcast();
    }
}
