// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

struct Bid {
    address payable bidder;
    uint amount; // in Gwei
    address bridge; // address of the bridge contract for that chain
    address lzEndpoint; // LayerZero endpoint of the chain of the bidder
}

enum MessageType {
    Bid_Submission, // 0
    Bid_Selection // 1
}

struct CrossChainMessage {
    MessageType messageType;
    bytes data;
}

contract MyOApp is OApp, ERC721URIStorage {

    // store bids for the tokens currently on this chain
    mapping (uint256=>Bid[]) bids;
    // store bids that have been submitted from this chain and are in process
    mapping (uint256=>Bid[]) extBids;
    // store the tokenURIs for all tokens that have ever been minted
    mapping (uint256=>string) allTokenURIs;

    constructor(address _endpoint, address _delegate) 
        OApp(_endpoint, _delegate) Ownable(_delegate) ERC721("crossAINFT", "CNFT") {}

    // Types of messages that a contract will receive are :
    // 1. Bid submission
    // 2. Successful bid selection

    receive() external payable {
        // decode the data
    }

    function makeBid(uint amount, uint tokenId) payable external {

    }

    function crossChainNFTTranser(uint256 tokenID, address recipient) external {}

    function sameChainNFTTransfer() external {}

    /**
     * @notice Sends a message from the source chain to a destination chain.
     * @param _dstEid The endpoint ID of the destination chain.
     * @param _message The message string to be sent.
     * @param _options Additional options for message execution.
     * @dev Encodes the message as bytes and sends it using the `_lzSend` internal function.
     * @return receipt A `MessagingReceipt` struct containing details of the message sent.
     */
    function send(
        uint32 _dstEid,
        string memory _message,
        bytes calldata _options
    ) external payable returns (MessagingReceipt memory receipt) {
        bytes memory _payload = abi.encode(_message);
        receipt = _lzSend(_dstEid, _payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    /**
     * @notice Quotes the gas needed to pay for the full omnichain transaction in native gas or ZRO token.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _message The message.
     * @param _options Message execution options (e.g., for sending gas to destination).
     * @param _payInLzToken Whether to return fee in ZRO token.
     * @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
     */
    function quote(
        uint32 _dstEid,
        string memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_message);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    function _sendBackMoneyOfBids(address payable successfulBidder, uint _tokenId) internal {
        Bid[] memory allBids = extBids[_tokenId];
        uint l = allBids.length;
        for(uint i=0;i<l;i++){
            if (allBids[i].bidder != successfulBidder){
                allBids[i].bidder.transfer(allBids[i].amount);
            }
        }
    }

    /**
     * @dev Internal function override to handle incoming messages from another chain.
     * @dev _origin A struct containing information about the message sender.
     * @dev _guid A unique global packet identifier for the message.
     * @param payload The encoded message payload being received.
     *
     * @dev The following params are unused in the current implementation of the OApp.
     * @dev _executor The address of the Executor responsible for processing the message.
     * @dev _extraData Arbitrary data appended by the Executor to the message.
     *
     * Decodes the received payload and processes it as per the business logic defined in the function.
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        (MessageType msgType, uint _tokenId, bytes memory data) = abi.decode(payload, (MessageType, uint256, bytes));
        if (msgType == MessageType.Bid_Submission){
            require(_ownerOf(_tokenId) != address(0), "The token does not exist on this chain");
            Bid memory bid = abi.decode(data, (Bid));
            bids[_tokenId].push(bid);
        }
        else if (msgType == MessageType.Bid_Selection) {
            Bid memory bid = abi.decode(data, (Bid));
            // humare yaha ka bacha select ho gya yaya
            // mint krdo, pesa transfer karwado
            // TODO: bridge the money
            // money will be transferred, now minting
            address payable selectedBidderAddress = bid.bidder;
            _mint(selectedBidderAddress, _tokenId);
            _setTokenURI(_tokenId, allTokenURIs[_tokenId]);
            // send back money of the other bidders
            _sendBackMoneyOfBids(selectedBidderAddress, _tokenId);
            delete extBids[_tokenId];
        }
    }

    
}