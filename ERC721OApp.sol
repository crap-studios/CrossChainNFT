// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";


struct Bid {
    address payable bidder;
    uint256 amount; // in Gwei
    uint32 lzEndpoint; // LayerZero endpoint of the chain of the bidder
}

// Types of messages that a contract will receive are :
    // 1. Bid submission
    // 2. Successful bid selection
    // 3. Minting of a token on a chain

enum MessageType {
    Bid_Submission, // 0
    Bid_Selection, // 1
    Token_Mint // 2
}

struct CrossChainMessage {
    MessageType messageType;
    bytes data;
}

contract MyOApp is OApp, ERC721URIStorage {

    // store bids for the tokens currently on this chain
    mapping (uint256=>Bid[]) public bids;
    // store bids that have been submitted from this chain and are in process
    mapping (uint256=>Bid[]) public extBids;
    // store the tokenURIs for all tokens that have ever been minted
    mapping (uint256=>string) public allTokenURIs;
    // store the bridge endpoints, mapped usign the lz endpoint addresses
    mapping (address=>address) public bridgeMapping;
    // store information about chain currently having some token
    mapping (uint256=>uint32) public tokenIdToLzEndpoint;

    uint32 public  eid;
    address public  chatbotAddress;
    // to have same tokenId minted across the chains for the same NFT, we give a part of the 
    // tokenId range that we have to each contract on each chain
    uint256 public startIdx;
    uint256 public endIdx;
    uint256 public tokenCounter;
    uint32[] eids;

    constructor(address _endpoint, address _delegate, address _chatbotAddress, uint256 _startIdx, uint256 _endIdx, uint32 _eid) 
        OApp(_endpoint, _delegate) Ownable(_delegate) ERC721("crossAINFT", "CNFT") {
            chatbotAddress = _chatbotAddress;
            startIdx=_startIdx;
            endIdx=_endIdx;
            tokenCounter=0;
            eid=_eid;
        }
    
    function addPeerEid(uint32 _eid, address contractAddress) external onlyOwner {
        _setPeer(_eid, bytes32(abi.encodePacked(contractAddress)));
        eids.push(_eid);
    }

    function changeChatbotAddress(address newChatbotAddress) external onlyOwner {
        chatbotAddress = newChatbotAddress;
    }

    function createNFT(string calldata tokenURI, address owner) external payable {
        // require(msg.sender == chatbotAddress, "Wrong address");
        uint256 tokenId = tokenCounter + startIdx;
        _mint(owner, tokenId);
        _setTokenURI(tokenId, tokenURI);
        tokenCounter++;
        uint l = eids.length;
        bytes memory msgPayload = abi.encode(MessageType.Token_Mint, tokenId, abi.encode(tokenURI));
        for (uint idx = 0; idx < l; idx++){
            _lzSend(eids[idx], msgPayload, bytes(""), MessagingFee(msg.value, 0), payable(msg.sender));
        }
    }

    function setBridge(address _destChainLzEndpoint, address _bridgeAddress) public onlyOwner {
        bridgeMapping[_destChainLzEndpoint] = _bridgeAddress;
    }

    function _putBid() internal returns (uint tokenId, Bid memory) {
        uint amount = msg.value;
        address payable bidder = payable (msg.sender);
        tokenId = abi.decode(msg.data, (uint256));
        Bid memory bid = Bid(bidder, amount, eid);
        extBids[tokenId].push(bid);
        return (tokenId, bid);
    }

    function _sendBidToNFTChainContract(Bid memory bid, uint256 tokenId) internal {
        bytes memory encodedBid = abi.encode(bid);
        bytes memory msgPayload = abi.encode(MessageType.Bid_Submission, tokenId, encodedBid);
        _lzSend(tokenIdToLzEndpoint[tokenId], msgPayload, bytes(""), MessagingFee(msg.value, 0), payable(msg.sender));
    }

    function _processBid() internal {
        (uint tokenId, Bid memory bid) = _putBid();        
        // send bid to the chain having this token
        _sendBidToNFTChainContract(bid, tokenId);
    }

    receive() external payable {
        // money will only be received when a bid has to be submitted
        _processBid();
    }

    function makeBid(uint _tokenId) external payable {
        uint amount = msg.value;
        address payable bidder = payable (msg.sender);
        Bid memory bid = Bid(bidder, amount, eid);
        extBids[_tokenId].push(bid);
        _sendBidToNFTChainContract(bid, _tokenId);
    }

    // tell if the msg sender's bid has been successfully placed
    function confirmBid(uint256 _tokenId, uint256 amount) external view returns (bool) {
        uint l = extBids[_tokenId].length;
        address payable payableAddress = payable(msg.sender);
        for(uint idx = 0; idx < l; idx++){
            if (extBids[_tokenId][idx].bidder == payableAddress && extBids[_tokenId][idx].amount == amount){
                return true;
            }
        }
        return false;
    }

    // get bids for a specific token (to be executed for a token on the caller's chain only)
    function getBidsByTokenId(uint256 _tokenId) external view returns (Bid[] memory) {
        return bids[_tokenId];
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

    function _sendBackMoneyOfAllBids(uint _tokenId) internal {
        Bid[] memory allBids = extBids[_tokenId];
        uint l = allBids.length;
        for(uint i=0;i<l;i++){
                allBids[i].bidder.transfer(allBids[i].amount);
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
        Origin calldata origin,
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
            // mint krdo, pesa transfer karwado
            // TODO: bridge the money
            // money will be transferred, now minting
            if (bid.lzEndpoint == eid) {
                // current chain's bid has been selected
                address payable selectedBidderAddress = bid.bidder;
                _mint(selectedBidderAddress, _tokenId);
                _setTokenURI(_tokenId, allTokenURIs[_tokenId]);
                // send back money of the other bidders
                _sendBackMoneyOfBids(selectedBidderAddress, _tokenId);
                delete extBids[_tokenId];
                tokenIdToLzEndpoint[_tokenId] = eid;
            }
            else {
                _sendBackMoneyOfAllBids(_tokenId);
                delete extBids[_tokenId];
                tokenIdToLzEndpoint[_tokenId] = bid.lzEndpoint;
            }
        } else if (msgType == MessageType.Token_Mint) {
            // decode the tokenid and the tokenURI and set it
            // srcEid is contained in origin
            string memory tokenURI = abi.decode(data, (string));
            allTokenURIs[_tokenId] = tokenURI;
            tokenIdToLzEndpoint[_tokenId] = origin.srcEid;
        }
    }

    
}