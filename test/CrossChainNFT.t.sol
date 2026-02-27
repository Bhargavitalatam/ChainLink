// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/CrossChainNFT.sol";

contract CrossChainNFTTest is Test {
    CrossChainNFT nft;
    address owner = address(1);
    address bridge = address(2);
    address user = address(3);

    function setUp() public {
        vm.startPrank(owner);
        nft = new CrossChainNFT("Test Name", "TST", owner);
        nft.setBridge(bridge);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(nft.name(), "Test Name");
        assertEq(nft.symbol(), "TST");
        assertEq(nft.owner(), owner);
        assertEq(nft.bridge(), bridge);
    }

    function test_MintOnlyByBridge() public {
        vm.startPrank(bridge);
        nft.mint(user, 1, "ipfs://test");
        vm.stopPrank();

        assertEq(nft.ownerOf(1), user);
        assertEq(nft.tokenURI(1), "ipfs://test");
    }

    function test_MintFailByNonBridge() public {
        vm.startPrank(user);
        vm.expectRevert("Caller is not the bridge");
        nft.mint(user, 1, "ipfs://test");
        vm.stopPrank();
    }

    function test_BurnByOwner() public {
        vm.startPrank(bridge);
        nft.mint(user, 1, "ipfs://test");
        vm.stopPrank();

        vm.startPrank(user);
        nft.burn(1);
        vm.stopPrank();

        vm.expectRevert(); // Should revert because token 1 burned
        nft.ownerOf(1);
    }

    function test_SetBridgeOnlyByOwner() public {
        vm.startPrank(owner);
        nft.setBridge(address(4));
        vm.stopPrank();
        assertEq(nft.bridge(), address(4));

        vm.startPrank(user);
        vm.expectRevert(); // Ownable revert
        nft.setBridge(address(5));
        vm.stopPrank();
    }
}
