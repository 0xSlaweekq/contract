// const fs = require('fs');
import { ethers, run } from 'hardhat';

async function main() {
  // let Data = JSON.parse(fs.readFileSync(`./data.json`));
  // const data = Data[0];
  //deploy token
  const Token = await ethers.getContractFactory('TokenERC20');
  const token = await Token.deploy();
  await token.deployed();
  console.log('deployed to:', token.address);
  //verify Token
  await new Promise(r => setTimeout(r, 5000));
  await run('verify:verify', {
    address: token.address,
    constructorArguments: []
  });
  // fs.writeFileSync(`./data.json`, JSON.stringify(newData, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
