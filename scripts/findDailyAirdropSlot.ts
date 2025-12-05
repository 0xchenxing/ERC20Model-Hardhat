import { ethers } from "hardhat";

async function main() {
  const [owner] = await ethers.getSigners();
  const BaseTokenFactory = await ethers.getContractFactory("BaseToken");
  const baseToken = await BaseTokenFactory.deploy(owner.address);
  await baseToken.waitForDeployment();

  // 触发一次空投以获得非零的dailyAirdropReleased
  await baseToken.connect(owner).claimAirdrop();

  const value = await baseToken.dailyAirdropReleased();
  const address = await baseToken.getAddress();
  const targetHex = ethers.hexZeroPad(ethers.toBeHex(value), 32);

  for (let slot = 0; slot < 50; slot++) {
    const slotHex = ethers.zeroPadValue(ethers.toBeHex(slot), 32);
    const storageValue = await ethers.provider.getStorageAt(address, slotHex);
    if (storageValue.toLowerCase() === targetHex.toLowerCase()) {
      console.log("Found slot:", slot);
      return;
    }
  }

  console.log("Slot not found");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});





