const customChains = [
  {
    // for mainnet
    network: 'base_mainnet',
    chainId: 8453,
    urls: {
      apiURL: 'https://api.basescan.org/api',
      browserURL: 'https://basescan.org'
    }
    // urls: {
    //     apiURL: 'https://base-mainnet.blockscout.com/api',
    //     browserURL: 'https://base-mainnet.blockscout.com'
    // }
  },
  {
    // for mainnet
    network: 'shibarium',
    chainId: 109,
    urls: {
      apiURL: 'https://api.shibariumscan.io/api',
      browserURL: 'https://shibariumscan.io/'
    }
  },
  {
    // for testnet
    network: 'base_goerli',
    chainId: 84531,
    urls: {
      apiURL: 'https://api-goerli.basescan.org/api',
      browserURL: 'https://goerli.basescan.org'
    }
    // urls: {
    //   apiURL: 'https://base-goerli.blockscout.com/api',
    //   browserURL: 'https://base-goerli.blockscout.com'
    // }
  },
  {
    network: 'celo',
    chainId: 42220,
    urls: {
      apiURL: 'https://api.celoscan.io/api',
      browserURL: 'https://celoscan.io'
    }
  },
  {
    network: 'arbitrum',
    chainId: 42161,
    urls: {
      apiURL: 'https://api.arbiscan.io/api',
      browserURL: 'https://arbiscan.io/'
    }
  },
  {
    network: 'optimism',
    chainId: 10,
    urls: {
      apiURL: 'https://api-optimistic.etherscan.io',
      browserURL: 'https://optimistic.etherscan.io/'
    }
  },
  {
    network: 'aurora',
    chainId: 1313161554,
    urls: {
      apiURL: 'https://api.aurorascan.dev/api',
      browserURL: 'https://aurorascan.dev/'
    }
  },
  {
    network: 'kava',
    chainId: 2222,
    urls: {
      apiURL: 'https://explorer.kava.io/api',
      browserURL: 'https://explorer.kava.io'
    }
  },
  {
    network: 'moonbeam',
    chainId: 1313161554,
    urls: {
      apiURL: 'https://api.aurorascan.dev/api',
      browserURL: 'https://moonbeam.moonscan.io/'
    }
  },
  {
    network: 'boba',
    chainId: 288,
    urls: {
      apiURL: 'https://api.bobascan.com/api',
      browserURL: 'https://bobascan.com/'
    }
  }
];
export default customChains;
