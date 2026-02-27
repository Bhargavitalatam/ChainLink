// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CrossChainNFT.sol";
import "../src/CCIPNFTBridge.sol";

contract DeployScript is Script {
    // Avalanche Fuji CCIP Config
    address constant FUJI_ROUTER = 0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8;
    address constant FUJI_LINK = 0x0b9D5D9136855f6FEC3C0993fEE6e9Ce1A297945;
    uint64 constant FUJI_CHAIN_SELECTOR = 14767482510784806043;

    // Arbitrum Sepolia CCIP Config
    address constant ARB_SEP_ROUTER = 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;
    address constant ARB_SEP_LINK = 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;
    uint64 constant ARB_SEP_CHAIN_SELECTOR = 3478487238524512106;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // RPC URLs
        string memory fujiRpc = vm.envString("FUJI_RPC_URL");
        string memory arbSepRpc = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");

        // Create forks
        uint256 fujiFork = vm.createSelectFork(fujiRpc);
        uint256 arbSepFork = vm.createFork(arbSepRpc);

        // --- DEPLOY ON FUJI ---
        vm.selectFork(fujiFork);
        vm.startBroadcast(deployerPrivateKey);
        
        CrossChainNFT fujiNFT = new CrossChainNFT("Cross Chain NFT", "CCNFT", deployer);
        CCIPNFTBridge fujiBridge = new CCIPNFTBridge(FUJI_ROUTER, FUJI_LINK, address(fujiNFT), deployer);
        
        // Pre-mint test NFT
        fujiNFT.setBridge(deployer);
        uint256 testTokenId = 1;
        fujiNFT.mint(deployer, testTokenId, "ipfs://test-uri-1");
        
        fujiNFT.setBridge(address(fujiBridge));
        fujiNFT.approve(address(fujiBridge), testTokenId);
        
        vm.stopBroadcast();

        // --- DEPLOY ON ARBITRUM SEPOLIA ---
        vm.selectFork(arbSepFork);
        vm.startBroadcast(deployerPrivateKey);
        
        CrossChainNFT arbSepNFT = new CrossChainNFT("Cross Chain NFT", "CCNFT", deployer);
        CCIPNFTBridge arbSepBridge = new CCIPNFTBridge(ARB_SEP_ROUTER, ARB_SEP_LINK, address(arbSepNFT), deployer);
        
        arbSepNFT.setBridge(address(arbSepBridge));
        
        vm.stopBroadcast();

        // --- CONFIGURE BRIDGES ---
        // Configure Fuji bridge with Arbitrum bridge address
        vm.selectFork(fujiFork);
        vm.startBroadcast(deployerPrivateKey);
        fujiBridge.setDestinationBridge(ARB_SEP_CHAIN_SELECTOR, address(arbSepBridge));
        vm.stopBroadcast();

        // Configure Arbitrum bridge with Fuji bridge address
        vm.selectFork(arbSepFork);
        vm.startBroadcast(deployerPrivateKey);
        arbSepBridge.setDestinationBridge(FUJI_CHAIN_SELECTOR, address(fujiBridge));
        vm.stopBroadcast();

        // --- WRITE DEPLOYMENT JSON ---
        string memory fujiObj = "fuji";
        vm.serializeAddress(fujiObj, "nftContractAddress", address(fujiNFT));
        string memory fujiJson = vm.serializeAddress(fujiObj, "bridgeContractAddress", address(fujiBridge));
        
        string memory arbObj = "arb";
        vm.serializeAddress(arbObj, "nftContractAddress", address(arbSepNFT));
        string memory arbJson = vm.serializeAddress(arbObj, "bridgeContractAddress", address(arbSepBridge));

        string memory deployObj = "deployment";
        vm.serializeString(deployObj, "avalancheFuji", fujiJson);
        string memory finalJson = vm.serializeString(deployObj, "arbitrumSepolia", arbJson);
        
        vm.writeJson(finalJson, "./deployment.json");
        
        console.log("Deployment completed!");
        console.log("Fuji NFT:", address(fujiNFT));
        console.log("Fuji Bridge:", address(fujiBridge));
        console.log("Arbitrum Sepolia NFT:", address(arbSepNFT));
        console.log("Arbitrum Sepolia Bridge:", address(arbSepBridge));
        console.log("Test NFT Token ID:", testTokenId);
    }
}
