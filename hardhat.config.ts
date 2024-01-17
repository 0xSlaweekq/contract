import 'hardhat-deploy';
import 'hardhat-abi-exporter';
import 'hardhat-gas-reporter';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
// import '@openzeppelin/hardhat-upgrades';
import '@typechain/hardhat';
import 'solidity-coverage';
import 'hardhat-contract-sizer';

import { HardhatUserConfig } from 'hardhat/config';
import { SolcUserConfig } from 'hardhat/types';
import path from 'path';

import apiKeys from './config/apiKeys';
import customChains from './config/customChains';
import networks from './config/networks';

const envConfig = require('dotenv').config({ path: path.resolve(__dirname, '.env') });
const { REPORT_GAS, TOKEN, GAS_PRICE_API, COINMARKETCAP_API_KEY } = envConfig.parsed || {};

/** @type import('hardhat/config').HardhatUserConfig */
const DEFAULT_COMPILER_SETTINGS: SolcUserConfig = {
  version: '0.8.22',
  settings: {
    optimizer: {
      enabled: true,
      runs: 1_000
    },
    metadata: {
      bytecodeHash: 'none'
    },
    evmVersion: 'shanghai'
  }
};
const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  paths: {
    tests: './test',
    artifacts: './build/artifacts',
    cache: './build/cache',
    deployments: './build/deployments'
  },
  typechain: {
    outDir: './build/typechain',
    target: 'ethers-v5'
  },
  networks: {
    hardhat: networks.hardhat,
    localhost: networks.localhost
  },
  etherscan: {
    apiKey: {
      hardhat: apiKeys.hardhat,
      localhost: apiKeys.localhost,
      mainnet: apiKeys.mainnet,
      goerli: apiKeys.goerli,
      bsc: apiKeys.bsc,
      bscTestnet: apiKeys.bscTestnet,
      polygon: apiKeys.polygon
    },
    customChains: customChains
  },
  solidity: {
    compilers: [
      DEFAULT_COMPILER_SETTINGS,
      {
        version: '0.8.16',
        settings: {
          optimizer: { enabled: true, runs: 1_000 },
          metadata: { bytecodeHash: 'none' }
        }
      },
      {
        version: '0.8.0',
        settings: {
          optimizer: { enabled: true, runs: 1_000 },
          metadata: { bytecodeHash: 'none' }
        }
      },
      {
        version: '0.6.0',
        settings: {
          optimizer: { enabled: true, runs: 1_000 },
          metadata: { bytecodeHash: 'none' }
        }
      }
    ]
  },
  contractSizer: {
    alphaSort: false,
    disambiguatePaths: true,
    runOnCompile: false
  },
  namedAccounts: {
    deployer: 0,
    admin: 1
  },
  // abiExporter: {
  //   path: './build/abis',
  //   runOnCompile: true,
  //   clear: true,
  //   flat: true,
  //   only: [],
  //   spacing: 2,
  //   pretty: true
  // },
  gasReporter: {
    enabled: REPORT_GAS === ('true' || true) ? true : false,
    noColors: true,
    outputFile: 'reports/gas_usage/summary.txt',
    currency: 'USD',
    coinmarketcap: COINMARKETCAP_API_KEY,
    token: TOKEN,
    gasPriceApi: GAS_PRICE_API,
    maxMethodDiff: 10
  },
  mocha: {
    timeout: 100000
  }
};
export default config;
