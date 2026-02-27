// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/CCIPNFTBridge.sol";
import "../src/CrossChainNFT.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract CCIPNFTBridgeTest is Test {
    CCIPNFTBridge bridge;
    CrossChainNFT nft;
    
    address owner = address(1);
    address router = address(0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8); // Fuji Router
    address link = address(0x0b9D5D9136855f6FEC3C0993fEE6e9Ce1A297945); // Fuji LINK
    address user = address(3);
    uint64 destChainSelector = 3478487238524512106; // Arbitrum Sepolia
    address destBridge = address(0x444);

    function setUp() public {
        vm.startPrank(owner);
        nft = new CrossChainNFT("Test", "T", owner);
        bridge = new CCIPNFTBridge(router, link, address(nft), owner);
        nft.setBridge(address(bridge));
        bridge.setDestinationBridge(destChainSelector, destBridge);
        vm.stopPrank();
    }

    function test_Setup() public {
        assertEq(address(bridge.nft()), address(nft));
        assertEq(address(bridge.router()), router);
        assertEq(bridge.destinationBridges(destChainSelector), destBridge);
    }

    function test_CcipReceive_Success() public {
        // Prepare message
        bytes memory payload = abi.encode(user, 10, "ipfs://uri");
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(123)),
            sourceChainSelector: destChainSelector,
            sender: abi.encode(destBridge),
            data: payload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        // Simulating call from router
        vm.prank(router);
        bridge.ccipReceive(message);

        assertEq(nft.ownerOf(10), user);
        assertEq(nft.tokenURI(10), "ipfs://uri");
    }

    function test_CcipReceive_RevertInvalidSender() public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(123)),
            sourceChainSelector: destChainSelector,
            sender: abi.encode(address(0xdead)), // Unregistered bridge
            data: abi.encode(user, 10, "uri"),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(router);
        vm.expectRevert("Invalid source bridge");
        bridge.ccipReceive(message);
    }

    function test_Idempotency() public {
        // First receive
        bytes memory payload = abi.encode(user, 10, "uri");
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(123)),
            sourceChainSelector: destChainSelector,
            sender: abi.encode(destBridge),
            data: payload,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.startPrank(router);
        bridge.ccipReceive(message);
        
        // Second receive of same tokenId - should not revert
        bridge.ccipReceive(message);
        vm.stopPrank();
        
        assertEq(nft.ownerOf(10), user);
    }
}
