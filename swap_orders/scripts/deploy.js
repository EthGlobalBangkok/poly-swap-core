const { ethers } = require("hardhat");

const SETTLEMENT = "0x9008D19f58AAbD9eD0D60971565AA8510560ab41";

// deploy the swap order factory contract
async function main() {
  const GATOrders = await ethers.getContractFactory("SwapOrderFactory");
  const orders = await GATOrders.deploy(SETTLEMENT);

  await orders.deployed();

  console.log(`SwapOrderFactory orders deployed to ${orders.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
