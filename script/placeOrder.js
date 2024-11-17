const { createPublicClient, createWalletClient, http, parseUnits } = require('viem');
const { privateKeyToAccount } = require('viem/accounts');
const { getContract } = require('viem');
const { gnosis } = require('viem/chains');
const fetch = require('node-fetch');
const crypto = require('crypto');
require('dotenv').config();

const ORDER_FACTORY = '0xF1D37c91cfE1C3bF137898CF89B96D196d02acCb';
const ONE_MINUTE = 60;

const WETH = '0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1';
const USDT = '0x4ecaba5870353805a9f068101a40e0f32ed605c6';

// import abi from json file
const SwapOrderFactoryABI = require('../abi/SwapOrderFactoryABI.json');
const IERC20ABI = require('../abi/IERC20ABI.json');

async function main() {
  // Initialize clients
  const privateKey = process.env.PRIVATE_KEY;
  const account = privateKeyToAccount(privateKey);

  const walletClient = createWalletClient({
    chain: gnosis,
    account,
    transport: http("https://gnosis-mainnet.g.alchemy.com/v2/RWAHqBV91p-N1AwdjyjksJUjxEogXOCn"),
  });

  const publicClient = createPublicClient({
    chain: gnosis,
    transport: http("https://gnosis-mainnet.g.alchemy.com/v2/RWAHqBV91p-N1AwdjyjksJUjxEogXOCn"),
  });

  // const weth = await getContract({
  //   address: WETH,
  //   abi: IERC20ABI,
  //   client: publicClient,
  // });

  // Check allowance
  // weth.read.allowance([account.address, ORDER_FACTORY]).then((allowance) => {
  //   if (allowance === BigInt(0)) {
  //     console.log(`Setting allowance ${account.address} to ${ORDER_FACTORY}`);
  //     walletClient.writeContract({
  //       address: WETH,
  //       abi: IERC20ABI,
  //       functionName: 'approve',
  //       args: [ORDER_FACTORY, BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')],
  //     }).then((tx) => {
  //       console.log('Allowance tx', tx);
  //     });
  //   }
  // });

  const now = Math.floor(Date.now() / 1000);
  const order = {
    sellToken: WETH,
    buyToken: USDT,
    receiver: '0xDcdD79bf63c1E8E2d54Ad2aBbB4342b152640B44', // Replace with your wallet address
    sellAmount: parseUnits('0.000001', 18),
    buyAmount: parseUnits('0.0002', 6),
    validTo: now + 20 * ONE_MINUTE,
    marketId: BigInt(1),
    marketWantedResult: BigInt(1),
    feeAmount: parseUnits('0.0005', 18),
    meta: '0x',
  };

  const salt = '0x' + crypto.randomBytes(32).toString('hex'); // Generate a random salt
  console.log('Order object:', order);
  console.log('Salt:', salt);

  console.log(`Placing order with ${account.address}`);
  let pl;
  let inst;
  let receipt
  try {
    const { result, request } = await publicClient.simulateContract({
      address: ORDER_FACTORY,
      abi: SwapOrderFactoryABI,
      functionName: 'placeWaitingSwap',
      args: [order, salt],
    });
    console.log('Simulation Result:', result);
    pl = result[0];
    inst = result[1];
    request.gas = 3000000
    const tx = await walletClient.writeContract(request);
    console.log('Transaction Hash:', tx);

    // Wait for the transaction receipt
    receipt = await publicClient.waitForTransactionReceipt({ hash: tx });
    console.log('Transaction Receipt:', receipt);
  } catch (error) {
    console.error('Error placing order:', error);
    process.exit(1);
  }
  console.log('Order placed :', pl, inst);

  const orderEvent = receipt.logs.find(
    (log) => log.eventName === 'OrderPlacement'
  );

  if (!orderEvent) {
    console.error('Order placement event not found.');
    process.exit(1);
  }

  const tokenTx = walletClient.writeContract({
    address: WETH,
    abi: IERC20ABI,
    functionName: 'transfer',
    args: [inst, order.sellAmount + order.feeAmount],
  }).then(async (tx) => {
    console.log('token tx hash', tx);
    const receiptToken = await publicClient.waitForTransactionReceipt({ hash: tokenTx });
    console.log('Token Receipt:', receiptToken);
  });

  // const { args: onchain } = orderEvent;

  // const offchain = {
  //   from: onchain.sender,
  //   sellToken: onchain.order.sellToken,
  //   buyToken: onchain.order.buyToken,
  //   receiver: onchain.order.receiver,
  //   sellAmount: onchain.order.sellAmount.toString(),
  //   buyAmount: onchain.order.buyAmount.toString(),
  //   validTo: onchain.order.validTo,
  //   appData: onchain.order.appData,
  //   feeAmount: onchain.order.feeAmount.toString(),
  //   kind: 'sell',
  //   partiallyFillable: onchain.order.partiallyFillable,
  //   sellTokenBalance: 'erc20',
  //   buyTokenBalance: 'erc20',
  //   signingScheme: 'eip1271',
  //   signature: onchain.signature.data,
  // };

  // const response = await fetch('https://api.WETH.fi/arbitrum_one/api/v1/orders', {
  //   method: 'POST',
  //   headers: {
  //     'Content-Type': 'application/json',
  //   },
  //   body: JSON.stringify(offchain),
  // });

  // const orderUid = await response.json();
  // console.log(orderUid);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
