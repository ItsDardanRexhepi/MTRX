const { expect } = require("chai");
const { ethers } = require("hardhat");

const NEOSAFE = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5";

describe("MTRX Contract Tests", function () {
  describe("OpenMatrixStaking", function () {
    let staking, owner, user;

    beforeEach(async function () {
      [owner, user] = await ethers.getSigners();
      const factory = await ethers.getContractFactory("OpenMatrixStaking");
      staking = await factory.deploy();
    });

    it("should deploy successfully", async function () {
      expect(staking.target).to.be.properAddress;
    });

    it("should have 5% commission rate", async function () {
      const rate = await staking.COMMISSION_BPS();
      expect(rate).to.equal(500); // 500 bps = 5%
    });

    it("should enforce 1 ETH minimum stake", async function () {
      await expect(
        staking.connect(user).stake({ value: ethers.parseEther("0.5") })
      ).to.be.revertedWith("Minimum 1 ETH");
    });

    it("should accept valid stake", async function () {
      await expect(
        staking.connect(user).stake({ value: ethers.parseEther("1.0") })
      ).to.not.be.reverted;
    });

    it("should route NeoSafe address correctly", async function () {
      const addr = await staking.NEOSAFE();
      expect(addr).to.equal(NEOSAFE);
    });
  });

  describe("Marketplace", function () {
    let marketplace, owner, seller, buyer;

    beforeEach(async function () {
      [owner, seller, buyer] = await ethers.getSigners();
      const factory = await ethers.getContractFactory("Marketplace");
      marketplace = await factory.deploy();
    });

    it("should deploy successfully", async function () {
      expect(marketplace.target).to.be.properAddress;
    });

    it("should have 5% platform fee", async function () {
      const fee = await marketplace.PLATFORM_FEE_BPS();
      expect(fee).to.equal(500); // 500 bps = 5%
    });

    it("should route fees to NeoSafe", async function () {
      const addr = await marketplace.NEOSAFE();
      expect(addr).to.equal(NEOSAFE);
    });
  });

  describe("PrivacyProtection", function () {
    let privacy, owner;

    beforeEach(async function () {
      [owner] = await ethers.getSigners();
      const factory = await ethers.getContractFactory("PrivacyProtection");
      privacy = await factory.deploy();
    });

    it("should deploy successfully", async function () {
      expect(privacy.target).to.be.properAddress;
    });

    it("should be irrevocable", async function () {
      const irrevocable = await privacy.IRREVOCABLE();
      expect(irrevocable).to.equal(true);
    });
  });

  describe("DisputeResolution", function () {
    let disputes, owner;

    beforeEach(async function () {
      [owner] = await ethers.getSigners();
      const factory = await ethers.getContractFactory("DisputeResolution");
      disputes = await factory.deploy();
    });

    it("should deploy successfully", async function () {
      expect(disputes.target).to.be.properAddress;
    });

    it("should require minimum 5 jurors", async function () {
      const min = await disputes.MIN_JURORS();
      expect(min).to.equal(5);
    });
  });

  describe("CommunityFundraising", function () {
    let fundraising, owner;

    beforeEach(async function () {
      [owner] = await ethers.getSigners();
      const factory = await ethers.getContractFactory("CommunityFundraising");
      fundraising = await factory.deploy();
    });

    it("should have zero platform fee", async function () {
      const fee = await fundraising.PLATFORM_FEE_BPS();
      expect(fee).to.equal(0);
    });
  });
});
