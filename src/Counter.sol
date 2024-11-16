// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OAppRead} from "@layerzero/oapp/OAppRead.sol";
// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Counter is OAppRead {
    constructor(address _endpoint, address _delegate) OAppRead(_endpoint, _delegate) Ownable(_delegate) {}
}
