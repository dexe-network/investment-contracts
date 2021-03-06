const { logTransaction } = require("../runners/logger/logger.js");

const Proxy = artifacts.require("TransparentUpgradeableProxy");
const ContractsRegistry = artifacts.require("ContractsRegistry");

const ERC20Mock = artifacts.require("ERC20Mock");

// BSC TESTNET
const usdAddress = "0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7"; // BUSD
const dexeAddress = "0xa651EdBbF77e1A2678DEfaE08A33c5004b491457";

module.exports = async (deployer) => {
  const contractsRegistry = await ContractsRegistry.at((await Proxy.deployed()).address);

  // const dexe = await deployer.deploy(ERC20Mock, "DEXE", "DEXE", 18);

  logTransaction(await contractsRegistry.addContract(await contractsRegistry.USD_NAME(), usdAddress), "Add USD");
  logTransaction(await contractsRegistry.addContract(await contractsRegistry.DEXE_NAME(), dexeAddress), "Add DEXE");
};
