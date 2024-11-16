require("@nomicfoundation/hardhat-toolbox")
require('dotenv').config()

module.exports = {
  solidity: "0.8.17",
  networks: {
    gnosis: {
      url: "https://rpc.gnosischain.com/",
      accounts: [process.env.PRIVATE_KEY],
    },
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: [process.env.PRIVATE_KEY],
    },
    arb_sep: {
      url: "https://arb-sepolia.g.alchemy.com/v2/RWAHqBV91p-N1AwdjyjksJUjxEogXOCn",
      accounts: [process.env.PRIVATE_KEY],
    },
  },
}
