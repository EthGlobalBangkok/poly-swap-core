// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// LZ
import {OAppRead} from "@layerzero/oapp/OAppRead.sol";
import {Origin} from "@layerzero/oapp/OApp.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {EVMCallRequestV1, EVMCallComputeV1} from "@layerzero/oapp/libs/ReadCmdCodecV1.sol";
import {ReadCodecV1} from "@layerzero-devtools/oapp/libs/ReadCmdCodecV1.sol";
// OZ
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// PM
import {CTFExchange} from "@polymarket/ctfe/exchange/CTFExchange.sol";
import {Order, OrderStatus} from "@polymarket/ctfe/libraries/OrderStructs.sol";

contract LayerZeroRead is OAppRead {
    /// lzRead responses are sent from arbitrary channels with Endpoint IDs in the range of
    /// `eid > 4294965694` (which is `type(uint32).max - 1600`).
    uint32 constant READ_CHANNEL_EID_THRESHOLD = 4294965694;

    constructor(address _endpoint, address _delegate) OAppRead(_endpoint, _delegate) Ownable(_delegate) {}

    /// @notice Internal function to handle incoming messages and read responses.
    /// @dev Filters messages based on `srcEid` to determine the type of incoming data.
    /// @param _origin The origin information containing the source Endpoint ID (`srcEid`).
    /// @param _guid The unique identifier for the received message.
    /// @param _message The encoded message data.
    /// @param _executor The executor address.
    /// @param _extraData Additional data.
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override {
        /**
         * @dev The `srcEid` (source Endpoint ID) is used to determine the type of incoming message.
         * - If `srcEid` is greater than READ_CHANNEL_EID_THRESHOLD (4294965694),
         *   it corresponds to arbitrary channel IDs for lzRead responses.
         * - All other `srcEid` values correspond to standard LayerZero messages.
         */
        if (_origin.srcEid > READ_CHANNEL_EID_THRESHOLD) {
            // Handle lzRead responses from arbitrary channels.
            _readLzReceive(_origin, _guid, _message, _executor, _extraData);
        } else {
            // Handle standard LayerZero messages.
            _messageLzReceive(_origin, _guid, _message, _executor, _extraData);
        }
    }

    /// @notice Internal function to handle standard LayerZero messages.
    /// @dev _origin The origin information (unused in this implementation).
    /// @dev _guid The unique identifier for the received message (unused in this implementation).
    /// @param _message The encoded message data.
    /// @dev _executor The executor address (unused in this implementation).
    /// @dev _extraData Additional data (unused in this implementation).
    function _messageLzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual {
        // Implement message handling logic here.
        bool _messageDoSomething = abi.decode(_message, (bool));
    }

    /// @notice Internal function to handle lzRead responses.
    /// @dev _origin The origin information (unused in this implementation).
    /// @dev _guid The unique identifier for the received message (unused in this implementation).
    /// @param _message The encoded message data.
    /// @dev _executor The executor address (unused in this implementation).
    /// @dev _extraData Additional data (unused in this implementation).
    function _readLzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual {
        // Implement lzRead response handling logic here.
        bool _readDoSomething = abi.decode(_message, (bool));
    }

    /**
     * @notice Constructs a command to query the Uniswap QuoterV2 for WETH/USDC prices on all configured chains.
     * @return cmd The encoded command to request Uniswap quotes.
     */
    function getCmd(bytes32 orderHash) public view returns (bytes memory) {
        // getOrderStatus() on the CTFExchange to know if a market is active or not

        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1(1);

        uint32 targetEid = 109;

        // OrderStatus memory orderStatus =

        // @notice Encode the function call
        // @dev From Uniswap Docs, this function is not marked view because it relies on calling non-view
        // functions and reverting to compute the result. It is also not gas efficient and should not
        // be called on-chain. We take advantage of lzRead to call this function off-chain and get the result
        // returned back on-chain to the OApp's _lzReceive method.
        // https://docs.uniswap.org/contracts/v3/reference/periphery/interfaces/IQuoterV2
        bytes memory callData = abi.encodeWithSelector(CTFExchange.getOrderStatus.selector, orderHash);

        readRequests[0] = EVMCallRequestV1({
            appRequestLabel: 0,
            targetEid: targetEid,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: 0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E, // CTFExchange address
            callData: callData
        });

        return ReadCodecV1.encode(0, readRequests, []);
    }

    /**
     * @notice Sends a read request to LayerZero, querying Uniswap QuoterV2 for WETH/USDC prices on configured chains.
     * @param _extraOptions Additional messaging options, including gas and fee settings.
     * @return receipt The LayerZero messaging receipt for the request.
     */
    function readAverageUniswapPrice(bytes calldata _extraOptions)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        bytes memory cmd = getCmd();
        return _lzSend(
            READ_CHANNEL,
            cmd,
            combineOptions(READ_CHANNEL, READ_MSG_TYPE, _extraOptions),
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
    }
}
