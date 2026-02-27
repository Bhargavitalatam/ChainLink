# Cross-Chain NFT Bridge

## Deployment & Configuration

The deployment script `script/Deploy.s.sol` requires the following environment variables. See `.env.example` for reference:
- `PRIVATE_KEY`: Your wallet private key.
- `FUJI_RPC_URL`: Avalanche Fuji testnet RPC URL.
- `ARBITRUM_SEPOLIA_RPC_URL`: Arbitrum Sepolia testnet RPC URL.

### Executing Deployment

You can run the deployment script as follows:
```bash
forge script script/Deploy.s.sol:DeployScript --broadcast --verify
```

### Pre-Minted Test NFT

During deployment, a test NFT is minted on the source chain (Avalanche Fuji) to test cross-chain bridging via Chainlink CCIP.

- **Source Chain**: Avalanche Fuji
- **Test NFT Token ID**: `1`
- **Initial Owner**: The deployer address

The deployed addresses for both networks are automatically stored in `deployment.json`.

## CLI Tool

The project includes a Node.js CLI tool located in the `cli/` directory to interact with the NFT bridge.

### Features
- Bridge NFTs across chains using Chainlink CCIP.
- Track NFT transfers and logs.
- Automated data logging in `data/nft_transfers.json` and `logs/transfers.log`.

### Running with Docker

The easiest way to run the CLI environment is using Docker Compose:

1.  **Environment Setup**: Copy `.env.example` to `.env` and fill in your details.
    ```bash
    cp .env.example .env
    ```
2.  **Start Container**:
    ```bash
    docker-compose up -d --build
    ```
3.  **Execute CLI**:
    ```bash
    docker exec -it ccip-nft-bridge-cli npm run transfer -- --tokenId=1 --from=avalanche-fuji --to=arbitrum-sepolia --receiver=0xYourReceiverAddress
    ```

### Manual Installation

1.  **Install Dependencies**:
    ```bash
    npm install
    ```
2.  **Run CLI**:
    ```bash
    node cli/bridge-cli.js --help
    ```

## FAQ

**Q: Where do I get testnet funds (AVAX, ETH) and LINK tokens?**
**A:** You can get testnet AVAX for Fuji and Sepolia ETH from public faucets. Chainlink provides faucets for LINK tokens on all supported testnets. You will need funds on both Avalanche Fuji and Arbitrum Sepolia.

**Q: My transaction is sent, but the NFT never arrives on the destination chain. What should I do?**
**A:** Use the [CCIP Explorer](https://ccip.chain.link/) with your CCIP Message ID (emitted in the `NFTSent` event) to track the status of your cross-chain message. It will show if the message is pending, delivered, or if it failed and why.

**Q: How does the bridge contract pay for the destination transaction?**
**A:** The `sendNFT` function on the source chain must approve and transfer LINK tokens to the CCIP Router. The router uses these tokens to pay for the gas costs of executing the `ccipReceive` function on the destination chain. The `estimateTransferCost` function helps determine the required amount.

**Q: Why are there two separate contracts (CCIPNFTBridge and CrossChainNFT)?**
**A:** This separation of concerns is a standard best practice. `CrossChainNFT` adheres to the ERC-721 standard for the token itself, while `CCIPNFTBridge` contains the complex, application-specific logic for cross-chain communication. This makes the system more modular and easier to maintain.

**Q: What should I put in the .env.example file?**
**A:** It should list all the environment variables needed to run your deployment scripts and CLI tool, with placeholder values. This includes your `PRIVATE_KEY`, RPC URLs for both chains, and the Chainlink Router and LINK token addresses.
