import path from 'path';

const envConfig = require('dotenv').config({ path: path.resolve(__dirname, '.env') });
/** @type import('hardhat/config').HardhatUserConfig */
const { POLYGONSCAN_API_KEY, BSCSCAN_API_KEY, ETHERSCAN_API_KEY } = envConfig.parsed || {};

const apiKeys = {
  hardhat: ETHERSCAN_API_KEY || 'API_KEY_WEB',
  localhost: ETHERSCAN_API_KEY || 'API_KEY_WEB',
  mainnet: ETHERSCAN_API_KEY || 'API_KEY_WEB',
  goerli: ETHERSCAN_API_KEY || 'API_KEY_WEB',
  // binance smart chain
  bsc: BSCSCAN_API_KEY || 'API_KEY_WEB',
  bscTestnet: BSCSCAN_API_KEY || 'API_KEY_WEB',
  // polygon
  polygon: POLYGONSCAN_API_KEY || 'API_KEY_WEB',
  polygonMumbai: POLYGONSCAN_API_KEY || 'API_KEY_WEB'
  // // base
  // base_mainnet: BASESCAN_API_KEY || 'API_KEY_WEB'
  // base_goerli: BASESCAN_API_KEY || 'API_KEY_WEB',
  // // shibarium
  // shibarium: '',
  // // fantom mainnet
  // opera: FANTOMSCAN_API_KEY || 'API_KEY_WEB',
  // ftmTestnet: FANTOMSCAN_API_KEY || 'API_KEY_WEB',
  // // avalanche
  // avalanche: AVALANCHE_API_KEY || 'API_KEY_WEB',
  // avalancheFujiTestnet: AVALANCHE_API_KEY || 'API_KEY_WEB',
  // // celo
  // celo: CELO_API_KEY || 'API_KEY_WEB',
  // // boba
  // boba: BOBA_API_KEY || 'API_KEY_WEB',
  // // cronos
  // cronos: CRONOS_API_KEY || 'API_KEY_WEB',
  // // aurora
  // aurora: AURORA_API_KEY || 'API_KEY_WEB',
  // // arbitrum
  // arbitrum: ARBITRUM_API_KEY || 'API_KEY_WEB',
  // // optimism
  // optimism: OPTIMISM_API_KEY || 'API_KEY_WEB',
  // // moonbeam
  // moonbeam: MOONBEAM_API_KEY || 'API_KEY_WEB',
  // // moonriver
  // moonriver: MOONRIVER_API_KEY || 'API_KEY_WEB'
};
export default apiKeys;
