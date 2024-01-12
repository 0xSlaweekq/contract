import path from 'path';

const envConfig = require('dotenv').config({ path: path.resolve(__dirname, '.env') });

/** @type import('hardhat/config').HardhatUserConfig */
const { INFURA_API_KEY, MNEMONIC, NODE_HOST, BLOCKNUMBER, PORT, NETWORK_ID } =
  envConfig.parsed || {};

const str = '1000000000000000000000000000000000000000000000000000000000000000';

const networks = {
  hardhat: {
    allowUnlimitedContractSize: true,
    loggingEnabled: false,
    // chainId: 137,
    // forking: {
    //   url: 'https://polygon-rpc.com',
    //   blockNumber: 34298636
    // },
    chainId: Number(NETWORK_ID),
    forking: {
      url: `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
      blockNumber: Number(BLOCKNUMBER)
    },
    accounts: {
      count: 100,
      mnemonic: MNEMONIC
    }
  },
  localhost: {
    chainId: Number(NETWORK_ID),
    url: `http://${NODE_HOST}:${PORT}`,
    // accounts: [`${PRIVATE_KEY1}`, `${PRIVATE_KEY2}`, `${PRIVATE_KEY3}`],
    accounts: { mnemonic: MNEMONIC || str }
  },
  eth: {
    url: `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
    chainId: 1,
    accounts: { mnemonic: MNEMONIC || str }
  },
  base_mainnet: {
    url: 'https://mainnet.base.org',
    accounts: { mnemonic: MNEMONIC || str },
    gasPrice: 1000000000
  },
  // for testnet
  base_goerli: {
    url: 'https://goerli.base.org',
    accounts: { mnemonic: MNEMONIC || str },
    gasPrice: 1000000000
  },
  // for local dev environment
  base_local: {
    url: 'http://localhost:8545',
    accounts: { mnemonic: MNEMONIC || str },
    gasPrice: 1000000000
  },
  shibarium: {
    url: 'https://www.shibrpc.com',
    chainId: 109,
    accounts: { mnemonic: MNEMONIC || str }
  },
  ropsten: {
    url: `https://ropsten.infura.io/v3/${INFURA_API_KEY}`,
    chainId: 3,
    accounts: { mnemonic: MNEMONIC || str }
  },
  rinkeby: {
    url: `https://rinkeby.infura.io/v3/${INFURA_API_KEY}`
  },
  goerli: {
    url: `https://goerli.infura.io/v3/${INFURA_API_KEY}`,
    chainId: 5,
    accounts: { mnemonic: MNEMONIC || str }
  },
  kovan: {
    url: `https://kovan.infura.io/v3/${INFURA_API_KEY}`,
    chainId: 42,
    accounts: { mnemonic: MNEMONIC || str },
    gasPrice: 8000000000
  },
  bscTest: {
    url: 'https://data-seed-prebsc-2-s2.binance.org:8545',
    chainId: 97,
    accounts: { mnemonic: MNEMONIC || str }
  },
  bsc: {
    url: 'https://api.ankr.com/bsc',
    // url: `https://bsc-dataseed.binance.org/`,
    chainId: 56,
    accounts: { mnemonic: MNEMONIC || str }
  },
  polygonMumbai: {
    url: `https://rpc-mumbai.maticvigil.com`,
    chainId: 80001,
    accounts: { mnemonic: MNEMONIC || str }
  },
  polygon: {
    url: `https://polygon-rpc.com`,
    // url: `https://rpc-mainnet.matic.quiknode.pro`,
    chainId: 137,
    accounts: { mnemonic: MNEMONIC || str }
  },
  avalanche: {
    url: `https://api.avax.network/ext/bc/C/rpc`,
    chainId: 43114,
    accounts: { mnemonic: MNEMONIC || str }
  },
  fantom: {
    // url: `https://rpc.testnet.fantom.network/`,https://rpc.ftm.tools/
    url: `https://rpc.ftm.tools/`,
    chainId: 250,
    accounts: { mnemonic: MNEMONIC || str }
  },
  moonriver: {
    url: `https://rpc.api.moonriver.moonbeam.network`,
    chainId: 1285,
    accounts: { mnemonic: MNEMONIC || str }
  },
  arbitrum: {
    url: `https://arb1.arbitrum.io/rpc`,
    chainId: 42161,
    accounts: { mnemonic: MNEMONIC || str }
  },
  aurora: {
    url: `https://mainnet.aurora.dev`,
    chainId: 1313161554,
    accounts: { mnemonic: MNEMONIC || str }
  },
  optimism: {
    url: `https://mainnet.optimism.io`,
    chainId: 10,
    accounts: { mnemonic: MNEMONIC || str }
  },
  moonbeam: {
    url: `https://rpc.api.moonbeam.network`,
    chainId: 1284,
    accounts: { mnemonic: MNEMONIC || str }
  },
  gnosis: {
    url: `https://rpc.gnosischain.com/`,
    chainId: 100,
    accounts: { mnemonic: MNEMONIC || str }
  },
  cronos: {
    url: `https://evm-cronos.crypto.org`,
    chainId: 25,
    accounts: { mnemonic: MNEMONIC || str }
  },
  fuse: {
    url: `https://rpc.fuse.io`,
    chainId: 122,
    accounts: { mnemonic: MNEMONIC || str }
  },
  okx: {
    url: `https://exchainrpc.okex.org`,
    chainId: 66,
    accounts: { mnemonic: MNEMONIC || str }
  },
  celo: {
    url: `https://celo.quickestnode.com`,
    chainId: 42220,
    accounts: { mnemonic: MNEMONIC || str }
  },
  boba: {
    url: `https://mainnet.boba.network`,
    chainId: 288,
    accounts: { mnemonic: MNEMONIC || str }
  },
  telos: {
    url: `https://mainnet.telos.net/evm`,
    chainId: 40,
    accounts: { mnemonic: MNEMONIC || str }
  },
  kava: {
    url: 'https://evm.kava.io',
    chainId: 2222,
    accounts: { mnemonic: MNEMONIC || str }
  },
  bitgert: {
    url: 'https://rpc.icecreamswap.com',
    chainId: 32520,
    accounts: { mnemonic: MNEMONIC || str }
  },
  metis: {
    url: 'https://andromeda.metis.io/?owner=1088',
    chainId: 1088,
    accounts: { mnemonic: MNEMONIC || str }
  },
  oasis: {
    url: 'https://emerald.oasis.dev',
    chainId: 42262,
    accounts: { mnemonic: MNEMONIC || str }
  }
};
export default networks;
