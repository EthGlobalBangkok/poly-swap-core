const { ethers } = require("hardhat")
const fetch = require("node-fetch")

const ORDER_FACTORY = "0x1D3e0742F9B754007404832B61606504E886Afe5"
const ONE_MINUTE = 60

const WETH = "0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1"
const USDT = "0x4ecaba5870353805a9f068101a40e0f32ed605c6"

async function main() {
  const [signer] = await ethers.getSigners()

  const orders = (await ethers.getContractAt("GATOrders", ORDER_FACTORY)).connect(
    signer
  )
  const weth = (await ethers.getContractAt("IERC20", WETH)).connect(signer)

  const allowance = await weth.allowance(signer.address, orders.address)
  if (allowance.eq(0)) {
    console.log(`setting allowance ${signer.address} to ${orders.address}`)
    const approval = await weth.approve(
      orders.address,
      ethers.constants.MaxUint256
    )
    await approval.wait()
  }

  const now = ~~(Date.now() / 1000)
  const order = {
    sellToken: weth.address,
    buyToken: USDT,
    receiver: "0xDcdD79bf63c1E8E2d54Ad2aBbB4342b152640B44", //my wallet address
    sellAmount: ethers.utils.parseUnits("0.00001", 18),
    buyAmount: ethers.utils.parseUnits("0.002", 6),
    validTo: now + 20 * ONE_MINUTE,
    feeAmount: ethers.utils.parseUnits("0.0005"),
    meta: "0x",
  }
  const salt = ethers.utils.id("salt")

  console.log(`placing order with ${signer.address}`)
  const placement = await orders.place(order, salt, { gasLimit: 5000000000 })
  const receipt = await placement.wait()

  const { args: onchain } = receipt.events.find(
    ({ event }) => event === "OrderPlacement"
  )
  const offchain = {
    from: onchain.sender,
    sellToken: onchain.order.sellToken,
    buyToken: onchain.order.buyToken,
    receiver: onchain.order.receiver,
    sellAmount: onchain.order.sellAmount.toString(),
    buyAmount: onchain.order.buyAmount.toString(),
    validTo: onchain.order.validTo,
    appData: onchain.order.appData,
    feeAmount: onchain.order.feeAmount.toString(),
    kind: "sell",
    partiallyFillable: onchain.order.partiallyFillable,
    sellTokenBalance: "erc20",
    buyTokenBalance: "erc20",
    signingScheme: "eip1271",
    signature: onchain.signature.data,
  }

  const response = await fetch(`https://api.USDT.fi/arbitrum_one/api/v1/orders`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify(offchain),
  })
  const orderUid = await response.json()

  console.log(orderUid)

  // For local debugging:
  //console.log(`curl -s 'http://localhost:8080/api/v1/orders' -X POST -H 'Content-Type: application/json' --data '${JSON.stringify(offchain)}'`)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
