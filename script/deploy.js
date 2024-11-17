const { ethers } = require("hardhat");

const SETTLEMENT = "0x9008D19f58AAbD9eD0D60971565AA8510560ab41";
const COMPOSABLE_COW = "0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74";

// deploy the swap order factory contract
async function main() {
  const GATOrders = await ethers.getContractFactory("SwapOrderFactory");
  const orders = await GATOrders.deploy(SETTLEMENT, COMPOSABLE_COW);

  await orders.deployed();

  console.log(`SwapOrderFactory orders deployed to ${orders.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
