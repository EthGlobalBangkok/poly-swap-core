// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppRead} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppRead.sol";
import {MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import {IOAppMapper} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppMapper.sol";
import {IOAppReducer} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReducer.sol";
import {
    ReadCodecV1,
    EVMCallComputeV1,
    EVMCallRequestV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import {Trading} from "polymarket-ctf-exchange/src/exchange/mixins/Trading.sol";
import {SwapWaitingOrder} from "./SwapWaitingOrder.sol";

contract LayerZeroRead is OAppRead, IOAppMapper, IOAppReducer {
    struct EvmReadRequest {
        uint16 appRequestLabel;
        uint32 targetEid;
        bool isBlockNum;
        uint64 blockNumOrTimestamp;
        uint16 confirmations;
        address to;
    }

    struct EvmComputeRequest {
        uint8 computeSetting;
        uint32 targetEid;
        bool isBlockNum;
        uint64 blockNumOrTimestamp;
        uint16 confirmations;
        address to;
    }

    uint8 internal constant COMPUTE_SETTING_MAP_ONLY = 0;
    uint8 internal constant COMPUTE_SETTING_REDUCE_ONLY = 1;
    uint8 internal constant COMPUTE_SETTING_MAP_REDUCE = 2;
    uint8 internal constant COMPUTE_SETTING_NONE = 3;

    bool public placeOrder = false;

    constructor(address _endpoint, address _delegate, string memory _identifier)
        OAppRead(_endpoint, _delegate)
        Ownable(_delegate)
    {
        identifier = _identifier;
    }

    string public identifier;
    bytes public data = abi.encode("Nothing received yet.");

    // address constant ctfExchange = 0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E; // mainnet
    address constant ctfExchange = 0xEC3975238884D8A5Aa0a3be1C098fd52C67b74D0; // sepolia base erc20 token

    /**
     * @notice Send a read command in loopback through channelId
     * @param _channelId Read Channel ID to be used for the message.
     * @param _appLabel The application label to use for the message.
     * @param _options Message execution options (e.g., for sending gas to destination).
     * @param orderHash Order hash to call on Polymarket
     * @dev Encodes the message as bytes and sends it using the `_lzSend` internal function.
     * @return receipt A `MessagingReceipt` struct containing details of the message sent.
     */
    function send(
        uint32 _channelId,
        uint16 _appLabel,
        bytes calldata _options,
        uint32 targetEid,
        SwapWaitingOrder swapWaitingOrder,
        bytes32 orderHash
    ) external payable returns (MessagingReceipt memory receipt) {
        bytes memory cmd = buildCmd(_appLabel, targetEid, orderHash);
        receipt = _lzSend(_channelId, cmd, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    /**
     * @notice Quotes the gas needed to pay for the full read command in native gas or ZRO token.
     * @param _channelId Read Channel ID to be used for the message.
     * @param _appLabel The application label to use for the message.
     * @param _options Message execution options (e.g., for sending gas to destination).
     * @param _payInLzToken Whether to return fee in ZRO token.
     * // TODO add param
     * @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
     */
    function quote(
        uint32 _channelId,
        uint16 _appLabel,
        bytes calldata _options,
        bool _payInLzToken,
        uint32 targetEid,
        bytes32 orderHash
    ) public view returns (MessagingFee memory fee) {
        bytes memory cmd = buildCmd(_appLabel, targetEid, orderHash);
        fee = _quote(_channelId, cmd, _options, _payInLzToken);
    }

    /**
     * @notice Builds the command to be sent
     * @param appLabel The application label to use for the message.
     * @return cmd The encoded command to be sent to to the channel.
     */
    function buildCmd(uint16 appLabel, uint32 targetEid, bytes32 orderHash) public view returns (bytes memory) {
        // build read requests
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](1);

        // bytes memory callData = abi.encodeWithSelector(ERC20.name.selector); // sepolia
        bytes memory callData = abi.encodeWithSelector(Trading.getOrderStatus.selector, orderHash); // mainnet

        readRequests[0] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: targetEid,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: ctfExchange,
            callData: callData
        });

        // EVMCallComputeV1 memory evmCompute = EVMCallComputeV1();
        bytes memory cmd = ReadCodecV1.encode(appLabel, readRequests); //, evmCompute);

        return cmd;
    }

    /**
     * @dev Internal function override to handle incoming messages from another chain.
     * @param payload The encoded message payload being received. This is the resolved command from the DVN
     *
     * @dev The following params are unused in the current implementation of the OApp.
     * @dev _origin A struct containing information about the message sender.
     * @dev _guid A unique global packet identifier for the message.
     * @dev _executor The address of the Executor responsible for processing the message.
     * @dev _extraData Arbitrary data appended by the Executor to the message.
     *
     * Decodes the received payload and processes it as per the business logic defined in the function.
     */
    function _lzReceive(
        Origin calldata, /*_origin*/
        bytes32, /*_guid*/
        bytes calldata payload,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) internal override {
        (bool isActive, uint256 remaining) = abi.decode(payload, (bool, uint256));
        placeOrder = !isActive;
    }

    function myInformation() public view returns (bytes memory) {
        return abi.encodePacked("_id:", identifier, "_blockNumber:", block.number);
    }

    function lzMap(bytes calldata _request, bytes calldata _response) external pure returns (bytes memory) {
        uint16 requestLabel = ReadCodecV1.decodeRequestV1AppRequestLabel(_request);
        return abi.encodePacked(_response, "_mapped_requestLabel:", requestLabel);
    }

    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory) {
        uint16 appLabel = ReadCodecV1.decodeCmdAppLabel(_cmd);
        bytes memory concatenatedResponses;

        for (uint256 i = 0; i < _responses.length; i++) {
            concatenatedResponses = abi.encodePacked(concatenatedResponses, _responses[i]);
        }
        return abi.encodePacked(concatenatedResponses, "_reduced_appLabel:", appLabel);
    }
}
