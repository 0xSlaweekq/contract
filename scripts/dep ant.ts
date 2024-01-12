import fs from 'fs';
import { ethers, run } from 'hardhat';

import Data from './data.json';

async function main() {
  // let Data = JSON.parse(fs.readFileSync(`./data.json`));
  //deploy token
  const Token = await ethers.getContractFactory('Test');
  const token = await Token.deploy(Data[0].name, Data[0].symbol, Data[0].flags, Data[0].feesAndLimits, Data[0].markAddr);
  await token.deployed();
  console.log('deployed to:', token.address);

  //verify Token
  await new Promise(r => setTimeout(r, 3000));
  await run('verify:verify', {
    address: token.address,
    constructorArguments: [Data[0].name, Data[0].symbol, Data[0].flags, Data[0].feesAndLimits, Data[0].markAddr]
  });
  const newData = await Data.map(obj => {
    return {
      token: token.address,
      name: obj.name,
      symbol: obj.symbol,
      flags: obj.flags,
      feesAndLimits: obj.feesAndLimits,
      markAddr: obj.markAddr
    };
  });
  fs.writeFileSync(`./data.json`, JSON.stringify(newData, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
