// SPDX-License-Identifier: 0BSD
pragma solidity ^0.8.17;

import {ICoWSwapSettlement} from "./interfaces/ICoWSwapSettlement.sol";
import {ERC1271_MAGIC_VALUE, IERC1271} from "./interfaces/IERC1271.sol";
// import { IERC20 } from "./interfaces/IERC20.sol";
//import { GPv2Order } from "./vendored/GPv2Order.sol";
import {GPv2Order, IERC20} from "../lib/cow-contracts/src/contracts/libraries/GPv2Order.sol";
import {ICoWSwapOnchainOrders} from "./vendored/ICoWSwapOnchainOrders.sol";
import {BaseConditionalOrder} from "../lib/composable-cow/src/BaseConditionalOrder.sol";
import {ComposableCoW} from "../lib/composable-cow/src/ComposableCoW.sol";

// --- error strings
/// @dev auction hasn't started
string constant AUCTION_NOT_STARTED = "auction not started";
/// @dev auction has already ended
string constant AUCTION_ENDED = "auction ended";
/// @dev auction has already been filled
string constant AUCTION_FILLED = "auction filled";
/// @dev can't buy and sell the same token
string constant ERR_SAME_TOKENS = "same tokens";
/// @dev sell amount must be greater than zero
string constant ERR_MIN_SELL_AMOUNT = "sellAmount must be gt 0";
/// @dev auction duration must be greater than zero
string constant ERR_MIN_AUCTION_DURATION = "auction duration is zero";
/// @dev step discount is zero
string constant ERR_MIN_STEP_DISCOUNT = "stepDiscount is zero";
/// @dev step discount is greater than or equal to 10000
string constant ERR_MAX_STEP_DISCOUNT = "stepDiscount is gte 10000";
/// @dev number of steps is less than or equal to 1
string constant ERR_MIN_NUM_STEPS = "numSteps is lte 1";
/// @dev total discount is greater than 10000
string constant ERR_MAX_TOTAL_DISCOUNT = "total discount is gte 10000";

contract SwapOrderFactory is ICoWSwapOnchainOrders {
    using GPv2Order for *;

    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        uint256 marketId;
        uint256 marketWantedResult;
        uint256 feeAmount;
        bytes meta;
    }

    bytes32 public constant APP_DATA = keccak256("PolySwap order");

    ICoWSwapSettlement public immutable settlement;
    bytes32 public immutable domainSeparator;

    event PolySwapOrder(address instance);

    ComposableCoW public immutable composableCow;

    constructor(ICoWSwapSettlement settlement_, ComposableCoW composableCow_) {
        settlement = settlement_;
        domainSeparator = settlement_.domainSeparator();
        composableCow = composableCow_;
    }

    // place a swap order that will be executed after the market result is known
    function placeWaitingSwap(Data calldata data, bytes32 salt)
        external
        returns (bytes memory orderUid, address instance)
    {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: data.sellToken,
            buyToken: data.buyToken,
            receiver: data.receiver == GPv2Order.RECEIVER_SAME_AS_OWNER ? msg.sender : data.receiver,
            sellAmount: data.sellAmount,
            buyAmount: data.buyAmount,
            validTo: data.validTo,
            appData: APP_DATA,
            feeAmount: data.feeAmount,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        bytes32 orderHash = order.hash(domainSeparator);

        SwapWaitingOrder waitingInstance = new SwapWaitingOrder{salt: salt}(
            msg.sender, data.sellToken, orderHash, data.marketId, data.marketWantedResult, settlement, composableCow
        );

        OnchainSignature memory signature = OnchainSignature({scheme: OnchainSigningScheme.Eip1271, data: hex""});

        emit PolySwapOrder(address(waitingInstance));
        emit OrderPlacement(
            address(waitingInstance),
            GPv2Order.Data({
                sellToken: data.sellToken,
                buyToken: data.buyToken,
                receiver: data.receiver == GPv2Order.RECEIVER_SAME_AS_OWNER ? msg.sender : data.receiver,
                sellAmount: data.sellAmount,
                buyAmount: data.buyAmount,
                validTo: data.validTo,
                appData: APP_DATA,
                feeAmount: data.feeAmount,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            signature,
            data.meta
        );

        orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderHash, address(waitingInstance), data.validTo);
        return (orderUid, address(waitingInstance));
    }
}
