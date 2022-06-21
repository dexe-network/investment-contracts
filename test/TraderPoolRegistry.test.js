const { assert } = require("chai");
const { accounts } = require("../scripts/helpers/utils");

const ContractsRegistry = artifacts.require("ContractsRegistry");
const TraderPoolRegistry = artifacts.require("TraderPoolRegistry");
const ERC20Mock = artifacts.require("ERC20Mock");

ContractsRegistry.numberFormat = "BigNumber";
TraderPoolRegistry.numberFormat = "BigNumber";
ERC20Mock.numberFormat = "BigNumber";

describe("TraderPoolRegistry", () => {
  let OWNER;
  let FACTORY;

  let token;
  let traderPoolRegistry;

  before("setup", async () => {
    OWNER = await accounts(0);
    FACTORY = await accounts(1);
  });

  beforeEach("setup", async () => {
    const contractsRegistry = await ContractsRegistry.new();
    const _traderPoolRegistry = await TraderPoolRegistry.new();
    token = await ERC20Mock.new("MOCK", "MOCK", 18);

    await contractsRegistry.__ContractsRegistry_init();

    await contractsRegistry.addContract(await contractsRegistry.POOL_FACTORY_NAME(), FACTORY);

    await contractsRegistry.addProxyContract(
      await contractsRegistry.TRADER_POOL_REGISTRY_NAME(),
      _traderPoolRegistry.address
    );

    traderPoolRegistry = await TraderPoolRegistry.at(await contractsRegistry.getTraderPoolRegistryContract());

    await traderPoolRegistry.__PoolContractsRegistry_init();

    await contractsRegistry.injectDependencies(await contractsRegistry.TRADER_POOL_REGISTRY_NAME());
  });

  describe("add and list pools", () => {
    let BASIC_NAME;
    let INVEST_NAME;

    let POOL_1;
    let POOL_2;
    let POOL_3;

    beforeEach("setup", async () => {
      BASIC_NAME = await traderPoolRegistry.BASIC_POOL_NAME();
      INVEST_NAME = await traderPoolRegistry.INVEST_POOL_NAME();

      POOL_1 = await accounts(3);
      POOL_2 = await accounts(4);
      POOL_3 = await accounts(5);
    });

    it("should successfully add and get implementation", async () => {
      await traderPoolRegistry.setNewImplementations([BASIC_NAME], [token.address]);

      assert.equal(await traderPoolRegistry.getImplementation(BASIC_NAME), token.address);
    });

    it("should successfully add new pools", async () => {
      await traderPoolRegistry.addPool(BASIC_NAME, POOL_1, { from: FACTORY });
      await traderPoolRegistry.addPool(BASIC_NAME, POOL_2, { from: FACTORY });

      assert.equal((await traderPoolRegistry.countPools(BASIC_NAME)).toFixed(), "2");
      assert.equal((await traderPoolRegistry.countPools(INVEST_NAME)).toFixed(), "0");

      assert.isTrue(await traderPoolRegistry.isBasicPool(POOL_2));
      assert.isFalse(await traderPoolRegistry.isInvestPool(POOL_1));

      assert.isFalse(await traderPoolRegistry.isPool(POOL_3));
      assert.isTrue(await traderPoolRegistry.isPool(POOL_2));
    });

    it("should successfully associate new pools", async () => {
      await traderPoolRegistry.associateUserWithPool(OWNER, BASIC_NAME, POOL_1, { from: FACTORY });
      await traderPoolRegistry.associateUserWithPool(OWNER, BASIC_NAME, POOL_2, { from: FACTORY });

      assert.equal((await traderPoolRegistry.countTraderPools(OWNER, BASIC_NAME)).toFixed(), "2");
      assert.equal((await traderPoolRegistry.countTraderPools(OWNER, INVEST_NAME)).toFixed(), "0");
    });

    it("should list added pools", async () => {
      await traderPoolRegistry.addPool(BASIC_NAME, POOL_1, { from: FACTORY });
      await traderPoolRegistry.addPool(BASIC_NAME, POOL_2, { from: FACTORY });

      assert.deepEqual(await traderPoolRegistry.listPools(BASIC_NAME, 0, 2), [POOL_1, POOL_2]);
      assert.deepEqual(await traderPoolRegistry.listPools(BASIC_NAME, 0, 10), [POOL_1, POOL_2]);
      assert.deepEqual(await traderPoolRegistry.listPools(BASIC_NAME, 1, 1), [POOL_2]);
      assert.deepEqual(await traderPoolRegistry.listPools(BASIC_NAME, 2, 0), []);
      assert.deepEqual(await traderPoolRegistry.listPools(INVEST_NAME, 0, 2), []);
    });

    it("should list associated pools", async () => {
      await traderPoolRegistry.associateUserWithPool(OWNER, BASIC_NAME, POOL_1, { from: FACTORY });
      await traderPoolRegistry.associateUserWithPool(OWNER, BASIC_NAME, POOL_2, { from: FACTORY });

      assert.deepEqual(await traderPoolRegistry.listTraderPools(OWNER, BASIC_NAME, 0, 2), [POOL_1, POOL_2]);
      assert.deepEqual(await traderPoolRegistry.listTraderPools(OWNER, BASIC_NAME, 0, 10), [POOL_1, POOL_2]);
      assert.deepEqual(await traderPoolRegistry.listTraderPools(OWNER, BASIC_NAME, 1, 1), [POOL_2]);
      assert.deepEqual(await traderPoolRegistry.listTraderPools(OWNER, BASIC_NAME, 2, 0), []);
      assert.deepEqual(await traderPoolRegistry.listTraderPools(OWNER, INVEST_NAME, 0, 2), []);
    });
  });
});
