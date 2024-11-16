// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LayerZeroRead} from "../src/LayerZeroRead.sol";

contract LayerZeroReadDeployer is Script {
    LayerZeroRead public lzread;

    function setUp() public {}

    function run() public {
        // bytes mescrimory deploycode = abi.encodePacked(type(SyncSafeModule).creationCode, safeProxyFactory, lzEndpoint, sender);

        // console.log(vmSafe.toString(deploycode));

        vm.broadcast();
        lzread =
            new LayerZeroRead(0x6EDCE65403992e310A62460808c4b910D972f10f, 0x47cee39389206557f88118A54EFDbCE13b28B6a4);
        vm.broadcast();
        // module.declarePeer(40245);
    }
}
