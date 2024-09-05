// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ONFT721 } from "@layerzerolabs/onft-evm/contracts/onft721/ONFT721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CrossChainNFT is ONFT721 {

    uint256 public tokenCounter;
    address private _chatBotContractAddress;

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) ONFT721(_name, _symbol, _lzEndpoint, _delegate) {
        tokenCounter = 0;
    }

    function setChatBotContractAddress(address contractAddress) external onlyOwner {
        _chatBotContractAddress = contractAddress;
    }

    function approvalRequired() external pure override returns (bool) {
        return false;
    }

    // so that only the chat bot contract can ask to mint NFTs
    modifier onlyChatBotContract {
        require(msg.sender == _chatBotContractAddress);
        _;
    }

    function createNFT(string memory tokenURI, address to) public onlyChatBotContract {
        // TODO: LayerZero
        // Currently making an extension at LayerZero to enable this functionality for the project
    }
}
