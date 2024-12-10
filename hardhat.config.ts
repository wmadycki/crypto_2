import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.27",
  networks: {
    ganache: {
      url: "http://127.0.0.1:8545",
      accounts: [process.env.PRIVATE_KEY || '0x...'],
      gas: 5000000,
      chainId: 1337,
    },
  },
};

export default config;
