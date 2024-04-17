// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "contract/trustToken.sol";



contract ValidatorNFT is ERC721, ERC721Enumerable, Ownable {


  uint256 private _nextTokenId = 0;
  uint256 public constant MAX_LEVEL = 2000;
  uint256 public constant TRUST_TOKEN_MINT_INTERVAL = 60 seconds; // Adjust as needed (seconds) // You'll need to convert minutes to seconds

  // TrustToken contract address
  address public trustToken; 

  // Mapping tokenId to minter address
  mapping(uint256 => address) public hasValidator;
  mapping(uint256 => uint256) public level;
  mapping(uint256 => uint256) public lastMintTime;
  mapping(address => uint256) public validatorTokenId;

  event LevelUp(address indexed owner, uint256 indexed tokenId, uint256 newLevel);
  event LevelReset(address indexed owner, uint256 indexed tokenId);
  event Minted(address indexed owner, uint256 indexed tokenId);

  constructor(address initialOwner) ERC721("Validator NFT", "UBSV") Ownable(initialOwner){}

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);   
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


  function safeMint(address to) internal  {
    uint256 tokenId = ++_nextTokenId;
    _safeMint(to, tokenId);
    
  }

  function _safeTransferFrom(address from, address to, uint256 tokenId) public {
    safeTransferFrom(from, to, tokenId);
    hasValidator[tokenId] = to;
    delete validatorTokenId[from];
    validatorTokenId[to] = tokenId;
  }

function hasValidatorTrue(address walletAddress) public view returns (bool) {
  uint256 tokenId = validatorTokenId[walletAddress];
  return tokenId != 0 && _exists(tokenId);  
}

  // Set the TrustToken contract address
  function setTrustToken(address _trustToken) public onlyOwner {
    trustToken = _trustToken;
  }

  // Mint function: Only 1 NFT per wallet, maps tokenId to minter address
  function mint() public {
    require(!hasValidatorTrue(msg.sender), "Only 1 NFT per wallet allowed");
    safeMint(msg.sender);
    uint256 tokenId = _nextTokenId;

    // Update both mappings
    hasValidator[tokenId] = msg.sender;
    validatorTokenId[msg.sender] = tokenId; // Store the token ID for the sender

    level[tokenId] = 1000; // Starting level set to 1
    lastMintTime[tokenId] = block.timestamp;
    emit Minted(msg.sender, tokenId);
  }
  function canMint(address owner) public view returns (bool) {
    return hasValidatorTrue(owner); // Only allow mint if user doesn't have one
  }

  function canMintForToken(uint256 tokenId, uint256 currentTime) public view returns (bool) {
    uint256 timeElapsed = currentTime - lastMintTime[tokenId]; // Calculate time difference
    return level[tokenId] < MAX_LEVEL && timeElapsed >= TRUST_TOKEN_MINT_INTERVAL; 
}

  function _exists(uint256 tokenId) internal view returns (bool) {
    return hasValidator[tokenId] != address(0); // Check if the owner address for the token ID is not the zero address    return false; // Replace with your actual implementation
  }

  function getLevel(uint256 tokenId) public view returns (uint256) {
    require(_exists(tokenId), "Token does not exist");
    return level[tokenId];
  }

  function getTimeUntilNextMint(uint256 tokenId) public view returns (uint256) {
    require(_exists(tokenId), "Token does not exist");
    uint256 timeElapsed = block.timestamp - lastMintTime[tokenId];
    return timeElapsed >= TRUST_TOKEN_MINT_INTERVAL ? 0 : TRUST_TOKEN_MINT_INTERVAL - timeElapsed;
  }

// Level up can only be called by the TrustToken contract
 function levelUpByValidator(uint256 tokenIdFrom, uint256 tokenIdto, address to, uint256 amount) public payable {
    require(_exists(tokenIdFrom), "Token (from) does not exist");
    require(_exists(tokenIdto), "Token (to) does not exist"); // Added validation 
    require(ownerOf(tokenIdFrom) == msg.sender, "Must own the token (from)");
    require(ownerOf(tokenIdto) == to, "Other wallet must own token (to)");
    require(level[tokenIdto] + (100 * amount) <= MAX_LEVEL, "Overflow protection"); // Protect against overflow

    // TrustToken burns tokens for the owner (msg.sender)
    TrustToken(trustToken).burnFor(msg.sender, amount);

    level[tokenIdto] += (100 * amount);
    lastMintTime[tokenIdto] = block.timestamp;
    emit LevelUp(msg.sender, tokenIdto, level[tokenIdto]);
  }

  // Timed trust token mint function (called automatically)
  function _autoMintTrustToken() internal {
    // Loop through all minted NFTs
    uint256 totalSupply = totalSupply();
    for (uint256 i = 0; i < totalSupply; i++) {
      uint256 tokenId = tokenByIndex(i);
      address owner = ownerOf(tokenId);
      
      // Check if enough time has passed for timed mint
      if (block.timestamp - lastMintTime[tokenId] >= TRUST_TOKEN_MINT_INTERVAL) {
        // Mint trust tokens to the NFT owner
        TrustToken(trustToken).mintByValidator(owner, 1); // Adjust mint amount as needed
        lastMintTime[tokenId] = block.timestamp;
      }
    }
  }

}