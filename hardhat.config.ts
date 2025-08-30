import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers"; // Required for ethers support
import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers"; // Ensure this matches the package

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxMochaEthersPlugin],
  mocha: {
    timeout: 40000
  },
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhat: {},
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "https://sepolia.infura.io/v3/YOUR_INFURA_API_KEY",
      accounts: [process.env.PRIVATE_KEY || "YOUR_PRIVATE_KEY"],
    },
  },
};

export default config;