// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
    IRouterClient
} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./CrossChainNFT.sol";

contract CCIPNFTBridge is CCIPReceiver, IERC721Receiver, Ownable {
    // Contract dependencies
    CrossChainNFT public immutable nft;
    IRouterClient public router;
    IERC20 public linkToken;

    // Mapping to store the bridge address for each destination chain
    mapping(uint64 => address) public destinationBridges;

    // Events
    event NFTSent(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId,
        string tokenURI
    );

    constructor(
        address _router,
        address _link,
        address _nft,
        address initialOwner
    ) CCIPReceiver(_router) Ownable(initialOwner) {
        router = IRouterClient(_router);
        linkToken = IERC20(_link);
        nft = CrossChainNFT(_nft);
    }

    // Function to configure the bridge address on a destination chain
    function setDestinationBridge(uint64 chainSelector, address bridgeAddress) external onlyOwner {
        destinationBridges[chainSelector] = bridgeAddress;
    }

    // Main function to initiate the NFT transfer
    function sendNFT(
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId
    ) external returns (bytes32 messageId) {
        address destinationBridge = destinationBridges[destinationChainSelector];
        require(destinationBridge != address(0), "Destination bridge not configured");

        // Get the token URI before burning
        string memory tokenURI = nft.tokenURI(tokenId);

        // Burn the NFT (requires user to have approved this contract)
        nft.burn(tokenId);

        // Encode the payload
        bytes memory payload = abi.encode(receiver, tokenId, tokenURI);

        // Construct the message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationBridge),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 400_000}) // Adjust gas limit as needed
            ),
            feeToken: address(linkToken)
        });

        // Initialize Router client
        IRouterClient routerClient = IRouterClient(this.getRouter());

        // Get fee
        uint256 fee = routerClient.getFee(destinationChainSelector, message);

        // Ensure sufficient LINK balance
        require(linkToken.balanceOf(address(this)) >= fee, "Not enough LINK for fee");

        // Approve router to spend LINK
        linkToken.approve(address(routerClient), fee);

        // Send the message
        messageId = routerClient.ccipSend(destinationChainSelector, message);

        emit NFTSent(messageId, destinationChainSelector, receiver, tokenId, tokenURI);

        return messageId;
    }

    // Callback function to receive messages from CCIP Router
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // SECURITY: Validate source chain and sender address
        address sender = abi.decode(message.sender, (address));
        require(destinationBridges[message.sourceChainSelector] == sender, "Invalid source bridge");

        // Decode the payload
        (address receiver, uint256 tokenId, string memory tokenURI) = abi.decode(
            message.data,
            (address, uint256, string)
        );

        // IDEMPOTENCY: Check if the tokenId already exists before minting
        try nft.ownerOf(tokenId) returns (address) {
            // Token already exists, skip minting to prevent revert and message failure
            return;
        } catch {
            // Token doesn't exist, proceed to mint
            nft.mint(receiver, tokenId, tokenURI);
        }
    }

    // Estimate transfer cost in LINK tokens
    function estimateTransferCost(uint64 destinationChainSelector) external view returns (uint256) {
        address destinationBridge = destinationBridges[destinationChainSelector];
        require(destinationBridge != address(0), "Destination bridge not configured");

        // Construct a dummy message for generic estimation
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationBridge),
            data: abi.encode(address(0), uint256(0), ""), // Minimal data payload
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 400_000}) 
            ),
            feeToken: address(linkToken)
        });

        // Initialize Router client
        IRouterClient routerClient = IRouterClient(this.getRouter());

        return routerClient.getFee(destinationChainSelector, message);
    }

    // Required for safe NFT transfers to this contract
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
