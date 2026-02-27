import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import "dotenv/config";
import { fileURLToPath } from 'url';
import crypto from 'crypto';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Chainlink CCIP Chain Selectors
const CHAIN_SELECTORS = {
  "avalanche-fuji": "14767482510784806043",
  "arbitrum-sepolia": "3478487238524512106"
};

const RPC_URLS = {
  "avalanche-fuji": process.env.FUJI_RPC_URL,
  "arbitrum-sepolia": process.env.ARBITRUM_SEPOLIA_RPC_URL
};

// Paths
const DEPLOYMENT_PATH = path.join(__dirname, "../deployment.json");
const BRIDGE_ABI_PATH = path.join(__dirname, "../out/CCIPNFTBridge.sol/CCIPNFTBridge.json");
const LOG_DIR = path.join(__dirname, "../logs");
const DATA_DIR = path.join(__dirname, "../data");
const LOG_FILE = path.join(LOG_DIR, "transfers.log");
const DATA_FILE = path.join(DATA_DIR, "nft_transfers.json");

// Utility to append to log file
function logTransfer(message) {
  const timestamp = new Date().toISOString();
  const logMessage = `[${timestamp}] ${message}\n`;
  fs.appendFileSync(LOG_FILE, logMessage);
  console.log(message);
}

// Utility to update transfers JSON (Requirement 13)
function updateTransfersData(transferId, data) {
  let transfers = [];
  if (fs.existsSync(DATA_FILE)) {
    try {
      const content = fs.readFileSync(DATA_FILE, "utf-8");
      const parsed = JSON.parse(content);
      transfers = Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      logTransfer("Error reading nft_transfers.json, creating new array");
    }
  }

  const index = transfers.findIndex(t => t.transferId === transferId);
  if (index !== -1) {
    transfers[index] = { ...transfers[index], ...data };
  } else {
    transfers.push({
      transferId,
      ...data,
      timestamp: new Date().toISOString()
    });
  }

  fs.writeFileSync(DATA_FILE, JSON.stringify(transfers, null, 2));
}

async function main() {
  // 1. Parse CLI arguments
  const argv = await yargs(hideBin(process.argv))
    .option("tokenId", {
      type: "string",
      description: "Token ID of the NFT to bridge",
      demandOption: true
    })
    .option("from", {
      type: "string",
      description: "Source chain (avalanche-fuji or arbitrum-sepolia)",
      demandOption: true,
      choices: ["avalanche-fuji", "arbitrum-sepolia"]
    })
    .option("to", {
      type: "string",
      description: "Destination chain (avalanche-fuji or arbitrum-sepolia)",
      demandOption: true,
      choices: ["avalanche-fuji", "arbitrum-sepolia"]
    })
    .option("receiver", {
      type: "string",
      description: "Address to receive the NFT on destination chain",
      demandOption: true
    })
    .check((argv) => {
      if (argv.from === argv.to) {
        throw new Error("Source and destination chains must be different");
      }
      return true;
    })
    .parse();

  // Ensure directories exist
  if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

  const transferId = crypto.randomUUID();

  // Initial record creation (initiated)
  updateTransfersData(transferId, {
    tokenId: argv.tokenId.toString(),
    sourceChain: argv.from,
    destinationChain: argv.to,
    receiver: argv.receiver,
    status: "initiated"
  });

  logTransfer(`Initiating transfer of tokenId ${argv.tokenId} from ${argv.from} to ${argv.to}`);

  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    logTransfer("ERROR: PRIVATE_KEY environment variable is required");
    updateTransfersData(transferId, { status: "failed" });
    process.exit(1);
  }

  // 2. Load contract ABIs and addresses
  if (!fs.existsSync(DEPLOYMENT_PATH)) {
    logTransfer("ERROR: deployment.json not found");
    updateTransfersData(transferId, { status: "failed" });
    process.exit(1);
  }

  const deployments = JSON.parse(fs.readFileSync(DEPLOYMENT_PATH, "utf-8"));

  if (!fs.existsSync(BRIDGE_ABI_PATH)) {
    logTransfer("ERROR: Bridge ABI not found. Compile contracts first.");
    updateTransfersData(transferId, { status: "failed" });
    process.exit(1);
  }
  const bridgeObjResponse = JSON.parse(fs.readFileSync(BRIDGE_ABI_PATH, "utf-8"));
  const bridgeAbi = bridgeObjResponse.abi;

  // Identify source bridge address
  let sourceBridgeAddress;
  if (argv.from === "avalanche-fuji") {
    sourceBridgeAddress = deployments.avalancheFuji.bridgeContractAddress;
  } else if (argv.from === "arbitrum-sepolia") {
    sourceBridgeAddress = deployments.arbitrumSepolia.bridgeContractAddress;
  }

  // 3. Connect to RPC
  const rpcUrl = RPC_URLS[argv.from];
  if (!rpcUrl) {
    logTransfer(`ERROR: RPC URL for ${argv.from} not found in .env`);
    updateTransfersData(transferId, { status: "failed" });
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  // 4. Instantiate source bridge contract
  const bridgeContract = new ethers.Contract(sourceBridgeAddress, bridgeAbi, wallet);

  // Ensure we have the destination chain CCIP selector
  const destinationChainSelector = CHAIN_SELECTORS[argv.to];

  // 5. Execute sendNFT transaction
  try {
    const sender = await wallet.getAddress();
    updateTransfersData(transferId, { sender });

    logTransfer(`Estimating transfer cost...`);
    logTransfer(`Using wallet address: ${sender}`);
    logTransfer(`Source bridge address: ${sourceBridgeAddress}`);

    updateTransfersData(transferId, { status: "in-progress" });

    logTransfer(`Broadcasting sendNFT(${destinationChainSelector}, ${argv.receiver}, ${argv.tokenId})`);

    const tx = await bridgeContract.sendNFT(
      destinationChainSelector,
      argv.receiver,
      argv.tokenId,
      { gasLimit: 1000000 }
    );

    logTransfer(`Transaction submitted. Hash: ${tx.hash}`);

    updateTransfersData(transferId, {
      sourceTxHash: tx.hash
    });

    logTransfer(`Waiting for transaction confirmation...`);
    const receipt = await tx.wait();

    logTransfer(`Transaction confirmed in block ${receipt.blockNumber}`);

    // Capture CCIP Message ID from logs
    // Simplified: in a real scenario we'd parse the receipt logs for NFTSent
    let ccipMessageId = "";
    try {
      const event = receipt.logs.map(log => {
        try { return bridgeContract.interface.parseLog(log); } catch (e) { return null; }
      }).find(e => e && e.name === 'NFTSent');
      if (event) ccipMessageId = event.args.messageId;
    } catch (e) {
      logTransfer("Could not parse NFTSent event for messageId");
    }

    updateTransfersData(transferId, {
      status: "completed",
      ccipMessageId: ccipMessageId
    });

    logTransfer(`Successfully initiated cross-chain transfer! MessageId: ${ccipMessageId}`);
  } catch (error) {
    logTransfer(`ERROR: Transaction failed - ${error.message}`);
    updateTransfersData(transferId, { status: "failed" });
    console.error(error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
