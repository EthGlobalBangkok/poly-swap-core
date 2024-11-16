// SPDX-License-Identifier: 0BSD
pragma solidity ^0.8.17;

import {ICoWSwapSettlement} from "./interfaces/ICoWSwapSettlement.sol";
import {ERC1271_MAGIC_VALUE, IERC1271} from "./interfaces/IERC1271.sol";
// import { IERC20 } from "./interfaces/IERC20.sol";
//import { GPv2Order } from "./vendored/GPv2Order.sol";
import {GPv2Order, IERC20} from "../lib/composable-cow/lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
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

// swap order placed after the market result is known
contract SwapWaitingOrder is IERC1271, BaseConditionalOrder {
    address public immutable owner;
    IERC20 public immutable sellToken;
    uint256 public immutable marketId;
    // var to store the market result that the owner wants to be a trigger for the order
    uint256 public immutable marketWantedResult;

    bool public placeOrder = false;

    bytes32 public orderHash;
    ComposableCoW public immutable composableCow;

    bytes32 public constant APP_DATA = keccak256("PolySwap order");

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
        // dutch auction specifics
        uint32 startTime; // 0 = mining time, > 0 = specific start time
        uint256 startBuyAmount;
        uint32 stepDuration; // measured in seconds
        uint256 stepDiscount; // measured in BPS (1/10000)
        uint256 numSteps;
        // nullifier
        uint256 buyTokenBalance; // monitor the current balance of `buyToken` to avoid replay attacks
    }

    constructor(
        address owner_,
        IERC20 sellToken_,
        bytes32 orderHash_,
        uint256 marketId_,
        uint256 marketWantedResult_,
        ICoWSwapSettlement settlement,
        ComposableCoW _composableCow
    ) {
        owner = owner_;
        sellToken = sellToken_;
        orderHash = orderHash_;
        marketId = marketId_;
        marketWantedResult = marketWantedResult_;
        composableCow = _composableCow;

        sellToken_.approve(settlement.vaultRelayer(), type(uint256).max);
    }

    // solver will call this function to check if the market condition is met
    function marketConditionMet() external returns (bool) {
        // call layer zero read to and check the result
        placeOrder = true;
        return true;
    }

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4 magicValue) {
        require(hash == orderHash, "invalid order");
        require(placeOrder, "market condition not met");
        magicValue = ERC1271_MAGIC_VALUE;
    }

    function cancel() public {
        require(msg.sender == owner, "not the owner");
        orderHash = bytes32(0);
        sellToken.transfer(owner, sellToken.balanceOf(address(this)));
    }

    function getTradeableOrder(address tmp_owner, address, bytes32 ctx, bytes calldata staticInput, bytes calldata)
        public
        view
        override
        returns (GPv2Order.Data memory)
    {
        GPv2Order.Data memory order;
        Data memory data = abi.decode(staticInput, (Data));
        _validateData(data);

        // `startTime` for the auction is either when the was mined or a specific start time
        if (data.startTime == 0) {
            data.startTime = uint32(uint256(composableCow.cabinet(tmp_owner, ctx)));
        }

        // woah there! you're too early and the auction hasn't started. Come back later.
        if (data.startTime > uint32(block.timestamp)) {
            revert PollTryAtEpoch(data.startTime, AUCTION_NOT_STARTED);
        }

        /**
         * @dev We bucket out the time from the auction's start to determine the step we are in.
         *      Unchecked:
         *      * Underflow: `block.timestamp - data.startTime` is always positive due to the above check.
         *      * Divison by zero: `data.stepDuration` is asserted to be non-zero in `validateData`.
         *      If `data.stepDuration` is consistently very large, resulting in the bucket always being zero,
         *      then the auction is effectively a fixed price sale with no discount.
         */
        uint32 bucket;
        unchecked {
            bucket = uint32(block.timestamp - data.startTime) / data.stepDuration;
        }

        // if too late, not valid, revert
        if (bucket >= data.numSteps) {
            revert PollNever(AUCTION_ENDED);
        }

        // calculate the current buy amount
        // Note: due to integer rounding, the current buy amount might be slightly lower than expected (off-by-one)
        uint256 bucketBuyAmount = data.startBuyAmount - (bucket * data.stepDiscount * data.startBuyAmount) / 10000;

        order = GPv2Order.Data(
            data.sellToken,
            data.buyToken,
            data.receiver,
            data.sellAmount,
            bucketBuyAmount,
            data.startTime + (bucket + 1) * data.stepDuration, // valid until the end of the current bucket
            APP_DATA,
            0, // use zero fee for limit orders
            GPv2Order.KIND_SELL, // only sell order support for now
            false, // partially fillable orders are not supported
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );

        /**
         * @dev We use the `buyTokenBalance`, ie. B(buyToken) to avoid replay attacks. Generally, this value will
         *      represent the user's balance of `buyToken` at the time of the order creation. We assert that if
         *      B(buyToken) + `bucketBuyAmount` >= B'(buyToken), then the order has already been filled.
         *      Considerations:
         *      1. A 'malicious' user gives `bucketBuyAmount` to the user after the order has been created.
         *         This is not a problem as the user has more effective `buyToken` than expected. This may be a
         *         problem if it results in a hook not being called that had a critical side effect.
         *      2. A user excitedly transfers `buyToken` to themselves after the order has been settled,
         *         and subsequently creates a new order in the next bucket. This presents UX issues that the
         *         SDK / front-end should handle - explicitly by ensuring that the `GPv2VaultRelayer` only has
         *         allowance to spend the exact `sellAmount` of `sellToken` for the order. This ensures
         *         that the user does not inadvertently trade again.
         */
        if (data.buyToken.balanceOf(address(order.receiver)) >= data.buyTokenBalance + bucketBuyAmount) {
            revert PollNever(AUCTION_FILLED);
        }
        if (placeOrder == false) {
            revert PollNever(AUCTION_NOT_STARTED);
        }
        return order;
    }

    /**
     * @dev External function for validating the ABI encoded data struct. Help debuggers!
     * @param data `Data` struct containing the order parameters
     * @dev Throws if the order provided is not valid.
     */
    function validateData(bytes memory data) external pure {
        _validateData(abi.decode(data, (Data)));
    }

    /**
     * Internal method for validating the ABI encoded data struct.
     * @dev This is a gas optimisation method as it allows us to avoid ABI decoding the data struct twice.
     * @param data `Data` struct containing the order parameters
     * @dev Throws if the order provided is not valid.
     */
    function _validateData(Data memory data) internal pure {
        if (data.sellToken == data.buyToken) revert OrderNotValid(ERR_SAME_TOKENS);
        if (data.sellAmount == 0) revert OrderNotValid(ERR_MIN_SELL_AMOUNT);
        if (data.stepDuration == 0) revert OrderNotValid(ERR_MIN_AUCTION_DURATION);
        if (data.stepDiscount == 0) revert OrderNotValid(ERR_MIN_STEP_DISCOUNT);
        if (data.stepDiscount >= 10000) revert OrderNotValid(ERR_MAX_STEP_DISCOUNT);
        if (data.numSteps <= 1) revert OrderNotValid(ERR_MIN_NUM_STEPS);
        if (data.numSteps * data.stepDiscount >= 10000) revert OrderNotValid(ERR_MAX_TOTAL_DISCOUNT);
    }
}
