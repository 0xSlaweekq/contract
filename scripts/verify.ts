// import fs from 'fs';
import { run } from 'hardhat';

async function main() {
  let Data = require(`./data.json`);
  let data = Data[0];
  //verify Token
  await new Promise(r => setTimeout(r, 3000));
  await run('verify:verify', {
    address: data.token,
    constructorArguments: []
  });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
