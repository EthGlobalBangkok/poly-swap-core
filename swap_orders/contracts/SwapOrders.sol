// SPDX-License-Identifier: 0BSD
pragma solidity ^0.8.17;

import { ICoWSwapSettlement } from "./interfaces/ICoWSwapSettlement.sol";
import { ERC1271_MAGIC_VALUE, IERC1271 } from "./interfaces/IERC1271.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { GPv2Order } from "./vendored/GPv2Order.sol";
import { ICoWSwapOnchainOrders } from "./vendored/ICoWSwapOnchainOrders.sol";

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

    bytes32 constant public APP_DATA = keccak256("PolySwap order");

    ICoWSwapSettlement immutable public settlement;
    bytes32 immutable public domainSeparator;

    constructor(ICoWSwapSettlement settlement_) {
        settlement = settlement_;
        domainSeparator = settlement_.domainSeparator();
    }

    // place a swap order that will be executed after the market result is known
    function placeWaitingSwap(
        Data calldata data,
        bytes32 salt
    ) external returns (bytes memory orderUid) {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: data.sellToken,
            buyToken: data.buyToken,
            receiver: data.receiver == GPv2Order.RECEIVER_SAME_AS_OWNER
                ? msg.sender
                : data.receiver,
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

        SwapWaitingOrder instance = new SwapWaitingOrder{salt: salt}(
            msg.sender,
            data.sellToken,
            orderHash,
            data.marketId,
            data.marketWantedResult,
            settlement
        );

        data.sellToken.transferFrom(
            msg.sender,
            address(instance),
            data.sellAmount + data.feeAmount
        );

        OnchainSignature memory signature = OnchainSignature({
            scheme: OnchainSigningScheme.Eip1271,
            data: hex""
        });

        emit OrderPlacement(address(instance), order, signature, data.meta);

        orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderHash, address(instance), data.validTo);
    }

    // place a swap order that is executed instantly
    function placeSwap(
        Data calldata data,
        bytes32 salt
    ) external returns (bytes memory orderUid) {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: data.sellToken,
            buyToken: data.buyToken,
            receiver: data.receiver == GPv2Order.RECEIVER_SAME_AS_OWNER
                ? msg.sender
                : data.receiver,
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

        SwapOrder instance = new SwapOrder{salt: salt}(
            msg.sender,
            data.sellToken,
            orderHash,
            settlement
        );

        data.sellToken.transferFrom(
            msg.sender,
            address(instance),
            data.sellAmount + data.feeAmount
        );

        OnchainSignature memory signature = OnchainSignature({
            scheme: OnchainSigningScheme.Eip1271,
            data: hex""
        });

        emit OrderPlacement(address(instance), order, signature, data.meta);

        orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderHash, address(instance), data.validTo);
    }
}

// swap order placed after the market result is known
contract SwapWaitingOrder is IERC1271 {
    address immutable public owner;
    IERC20 immutable public sellToken;
    uint256 immutable public marketId;
    // var to store the market result that the owner wants to be a trigger for the order
    uint256 immutable public marketWantedResult;

    bool public placeOrder = false;

    bytes32 public orderHash;

    constructor(
        address owner_,
        IERC20 sellToken_,
        bytes32 orderHash_,
        uint256 marketId_,
        uint256 marketWantedResult_,
        ICoWSwapSettlement settlement
    ) {
        owner = owner_;
        sellToken = sellToken_;
        orderHash = orderHash_;
        marketId = marketId_;
        marketWantedResult = marketWantedResult_;

        sellToken_.approve(settlement.vaultRelayer(), type(uint256).max);
    }

    // solver will call this function to check if the market condition is met
    function marketConditionMet() external returns (bool) {
        // call layer zero read to and check the result
        return true;
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata
    ) external view returns (bytes4 magicValue) {
        require(hash == orderHash, "invalid order");
        require(placeOrder, "market condition not met");
        magicValue = ERC1271_MAGIC_VALUE;
    }

    function cancel() public {
        require(msg.sender == owner, "not the owner");
        orderHash = bytes32(0);
        sellToken.transfer(owner, sellToken.balanceOf(address(this)));
    }
}

// swap order placed instantly
contract SwapOrder is IERC1271 {
    address immutable public owner;
    IERC20 immutable public sellToken;

    bytes32 public orderHash;

    constructor(
        address owner_,
        IERC20 sellToken_,
        bytes32 orderHash_,
        ICoWSwapSettlement settlement
    ) {
        owner = owner_;
        sellToken = sellToken_;
        orderHash = orderHash_;

        sellToken_.approve(settlement.vaultRelayer(), type(uint256).max);
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata
    ) external view returns (bytes4 magicValue) {
        require(hash == orderHash, "invalid order");
        magicValue = ERC1271_MAGIC_VALUE;
    }

    function cancel() public {
        require(msg.sender == owner, "not the owner");
        orderHash = bytes32(0);
        sellToken.transfer(owner, sellToken.balanceOf(address(this)));
    }
}
