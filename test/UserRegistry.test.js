const ethSigUtil = require("@metamask/eth-sig-util");
const { assert } = require("chai");
const { web3 } = require("hardhat");
const { accounts } = require("../scripts/helpers/utils");
const truffleAssert = require("truffle-assertions");

const ContractsRegistry = artifacts.require("ContractsRegistry");
const UserRegistry = artifacts.require("UserRegistry");

ContractsRegistry.numberFormat = "BigNumber";
UserRegistry.numberFormat = "BigNumber";

describe("UserRegistry", () => {
  let OWNER;
  let OWNER_PRIVATE_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

  let userRegistry;
  let userRegistryName;

  before("setup", async () => {
    OWNER = await accounts(0);
  });

  beforeEach("setup", async () => {
    const contractsRegistry = await ContractsRegistry.new();
    const _userRegistry = await UserRegistry.new();

    await contractsRegistry.__ContractsRegistry_init();

    userRegistryName = await contractsRegistry.USER_REGISTRY_NAME();

    await contractsRegistry.addProxyContract(userRegistryName, _userRegistry.address);

    userRegistry = await UserRegistry.at(await contractsRegistry.getUserRegistryContract());

    await userRegistry.__UserRegistry_init(userRegistryName);
  });

  async function sign(hash, userPrivateKey) {
    const privateKey = Buffer.from(userPrivateKey, "hex");

    const EIP712Domain = [
      { name: "name", type: "string" },
      { name: "version", type: "string" },
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" },
    ];

    const Agreement = [{ name: "documentHash", type: "bytes32" }];

    const domain = {
      name: userRegistryName,
      version: "1",
      chainId: 31337,
      verifyingContract: userRegistry.address,
    };

    const message = {
      documentHash: hash,
    };

    const data = {
      primaryType: "Agreement",
      types: { EIP712Domain, Agreement },
      domain: domain,
      message: message,
    };

    return ethSigUtil.signTypedData({
      privateKey,
      data: data,
      version: "V4",
    });
  }

  describe("Privacy Policy signature", () => {
    it("should sign the privacy policy", async () => {
      const docHash = web3.utils.soliditySha3("Privacy Policy document content");
      const signature = await sign(docHash, OWNER_PRIVATE_KEY);

      assert.isFalse(await userRegistry.agreed(OWNER));

      await userRegistry.setPrivacyPolicyDocumentHash(docHash);
      await userRegistry.agreeToPrivacyPolicy(signature);

      assert.equal(await userRegistry.documentHash(), docHash);
      assert.isTrue(await userRegistry.agreed(OWNER));
    });

    it("should not agree to wrong policy", async () => {
      const docHash = web3.utils.soliditySha3("Privacy Policy document content");
      const wrongDocHash = web3.utils.soliditySha3("BAD DOC");
      const signature = await sign(wrongDocHash, OWNER_PRIVATE_KEY);

      await userRegistry.setPrivacyPolicyDocumentHash(docHash);
      await truffleAssert.reverts(userRegistry.agreeToPrivacyPolicy(signature), "UserRegistry: invalid signature");
    });
  });

  describe("Profile", () => {
    it("should set new profile URL", async () => {
      assert.equal((await userRegistry.userInfos(OWNER)).profileURL, "");

      await userRegistry.changeProfile("example.com");

      assert.equal((await userRegistry.userInfos(OWNER)).profileURL, "example.com");
    });
  });

  describe("Profile & policy", () => {
    it("should set new profile and agree to policy", async () => {
      const docHash = web3.utils.soliditySha3("Privacy Policy document content");
      const signature = await sign(docHash, OWNER_PRIVATE_KEY);

      await userRegistry.setPrivacyPolicyDocumentHash(docHash);
      await userRegistry.changeProfileAndAgreeToPrivacyPolicy("example.com", signature);

      assert.isTrue(await userRegistry.agreed(OWNER));
      assert.equal((await userRegistry.userInfos(OWNER)).profileURL, "example.com");
    });
  });
});
