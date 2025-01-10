import { Account, CallData, Contract, RpcProvider, stark } from "starknet";
import * as dotenv from "dotenv";
import { getCompiledCode } from "./utils";
dotenv.config();

async function main() {
  const provider = new RpcProvider({
    nodeUrl: process.env.RPC_ENDPOINT,
  });

  // initialize existing predeployed account 0
  console.log("ACCOUNT_ADDRESS=", process.env.DEPLOYER_ADDRESS);
  const privateKey0 = process.env.DEPLOYER_PRIVATE_KEY ?? "";
  const accountAddress0: string = process.env.DEPLOYER_ADDRESS ?? "";
  const account0 = new Account(provider, accountAddress0, privateKey0);
  console.log("Account connected.\n");

  // Declare & deploy contract
  let sierraCode,
    casmCode,
    sierraCodeLifeSourceManager,
    casmCodLifeSourceManager;

  try {
    ({ sierraCode, casmCode } = await getCompiledCode(
      "match_starknet_contracts_ERC20"
    ));
    ({
      sierraCode: sierraCodeLifeSourceManager,
      casmCode: casmCodLifeSourceManager,
    } = await getCompiledCode("match_starknet_contracts_LifeSourceManager"));
  } catch (error: any) {
    console.log("Failed to read contract files");
    console.log(error);
    process.exit(1);
  }

  const declareResponse = await account0.declareIfNot({
    contract: sierraCode,
    casm: casmCode,
  });

  const myCallDataLifeSource = new CallData(sierraCodeLifeSourceManager.abi);

  const constructorLifeSource = myCallDataLifeSource.compile("constructor", {
    class_hash: declareResponse.class_hash,
  });

  const deployResponse = await account0.declareAndDeploy({
    contract: sierraCodeLifeSourceManager,
    casm: casmCodLifeSourceManager,
    constructorCalldata: constructorLifeSource,
    salt: stark.randomAddress(),
  });

  // Connect the new contract instance :
  const lifeSourceContract = new Contract(
    sierraCodeLifeSourceManager.abi,
    deployResponse.deploy.contract_address,
    provider
  );
  console.log(
    `✅ Contract has been deploy with the address: ${lifeSourceContract.address}`
  );
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
