// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../node_modules/@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./chickenToken.sol";

contract Chicken is ERC721Enumerable, RrpRequesterV0 {
  struct ChickenInfo {
    uint256 tokenId;
    string tokenInfo;
    uint256 eggLevel;
    uint256 nextTimeToLay;
    address owner;
  }
  enum HatchStatus {
    None,
    Pending,
    Hatched,
    NotHatched
  }

  using Strings for uint256;

  uint256 public SECONDS_BETWEEN_LAYS = 28800; // 8 hours
  string public BASE_TOKEN_URI = "ipfs://QmdTThZYNZ2a7mDCrFqN5u5LhnpbYbQUxXmG83S7ycByng/";

  uint256 public MIN_LEVEL = 1;
  uint256 public MAX_LEVEL = 20;
  uint256 public lastTokenId;

  // oracle set up
  address public airnode; // The address of the QRNG Airnode
  bytes32 public endpointIdUint256; // The endpoint ID for requesting a single random number
  address public sponsorWallet; // The wallet that will cover the gas costs of the request

  // hatch requests
  mapping (bytes32 => address) public hatchOwner;
  mapping (bytes32 => HatchStatus) public hatchStatus;

  bool public canAirdrop = true;

  address public partyAddress;
  EggToken public eggToken;

  mapping(uint256 => uint256) public eggLevel;
  mapping(uint256 => uint256) public nextTimeToLay;


  event EggsLaid(address indexed owner, uint256 indexed tokenId, uint256 eggAmount);
  event FedChicken(address indexed owner, uint256 indexed tokenId, uint256 numberOfEggs);
  event EggThrown(address indexed attacker, address indexed victim, uint256 indexed victimChickenId, uint256 numberOfEggs);
  event LevelChanged(address indexed owner, uint256 indexed tokenId, uint256 oldLevel, uint256 newLevel);
  event HatchSucceeded(address indexed owner, bytes32 requestId);
  event HatchFailed(address indexed owner, bytes32 requestId);

  modifier onlyParty() {
    require(msg.sender == partyAddress, "caller is not the party");
    _;
  }

  constructor(address _partyAddress, EggToken _eggToken, address _airnodeRrp) ERC721("Egg Wars Chicken", "EWC") RrpRequesterV0(_airnodeRrp) {
    partyAddress = _partyAddress;
    eggToken = _eggToken;
  }

  function setAirnode(address _airnode, bytes32 _endpointIdUint256, address _sponsorWallet) public onlyParty {
    airnode = _airnode;
    endpointIdUint256 = _endpointIdUint256;
    sponsorWallet = _sponsorWallet;
  }

  function airdrop(address[] calldata to) public onlyParty {
    require(canAirdrop, "airdrop not active");

    for (uint256 i = 0; i < to.length; i++) {
      _birthChicken(to[i]);
    }
  }

  function closeAirdrop() public onlyParty {
    canAirdrop = false;
  }

  function layEggs(uint256[] calldata tokenIds) public {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 curTokenId = tokenIds[i];

      require(ownerOf(curTokenId) == msg.sender, "caller is not the owner of the token");
      require(canLayEggsNow(curTokenId), "not time to lay yet");

      nextTimeToLay[curTokenId] = block.timestamp + SECONDS_BETWEEN_LAYS;

      uint256 eggsToMint = eggLevel[curTokenId] * 10**18;
      eggToken.mintFor(msg.sender, eggsToMint);
      emit EggsLaid(msg.sender, curTokenId, eggsToMint);
    }
  }
  
  function canLayEggsNow(uint256 tokenId) public view returns (bool) {
    return block.timestamp >= nextTimeToLay[tokenId];
  }

  function feed(uint256 numberOfEggs, uint256 tokenIdToPowerUp) public {
    require(ownerOf(tokenIdToPowerUp) == msg.sender, "must own chicken");
    require(eggToken.balanceOf(msg.sender) >= numberOfEggs, "not enough eggs");

    eggToken.burnFor(msg.sender, numberOfEggs * 10**18);
    _increaseLevel(tokenIdToPowerUp, numberOfEggs);
    emit FedChicken(msg.sender, tokenIdToPowerUp, numberOfEggs);
  }

  function throwEgg(uint256 numberOfEggsToThrow, uint256 tokenIdToAttack) public {
    require(balanceOf(msg.sender) >= 1, "must own chicken");
    require(eggToken.balanceOf(msg.sender) >= numberOfEggsToThrow, "not enough eggs");
    eggToken.burnFor(msg.sender, numberOfEggsToThrow * 10 ** 18);
    _decreaseLevel(tokenIdToAttack, numberOfEggsToThrow);
    emit EggThrown(msg.sender, ownerOf(tokenIdToAttack), tokenIdToAttack, numberOfEggsToThrow);
  }

  function requestHatch() public {
    require(eggToken.balanceOf(msg.sender) >= 1 ether, "not enough eggs");
    eggToken.burnFor(msg.sender, 1 ether);

    bytes32 requestId = airnodeRrp.makeFullRequest(
        airnode,
        endpointIdUint256,
        address(this),
        sponsorWallet,
        address(this),
        this.randomNumberReceived.selector,
        ""
    );
    hatchStatus[requestId] = HatchStatus.Pending;
    hatchOwner[requestId] = msg.sender;
  }

  function randomNumberReceived(
      bytes32 requestId,
      bytes calldata data
  ) external onlyAirnodeRrp {
    if ((hatchStatus[requestId] == HatchStatus.Pending)) {
      revert('hatch not pending');
    }
    address hatchOwnerAddress = hatchOwner[requestId];
    if (hatchOwnerAddress == address(0)) {
      revert('no owner');
    }

    uint256 randomUint256 = abi.decode(data, (uint256));
    bool birthWorked = (randomUint256 % 100) <= 15;
    if (birthWorked) {
      hatchStatus[requestId] = HatchStatus.Hatched;
      _birthChicken(hatchOwnerAddress);
      emit HatchSucceeded(hatchOwnerAddress, requestId);
    } else {
      hatchStatus[requestId] = HatchStatus.NotHatched;
      emit HatchFailed(hatchOwnerAddress, requestId);
    }
  }

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    require(eggLevel[tokenId] > 0, "token not minted");
    return string(
        abi.encodePacked(
            "data:application/json;base64,",
            tokenData(tokenId)
        )
    );
  }

 function tokenData(uint256 tokenId) public view virtual returns (string memory) {
      uint _chickenType = tokenId % 4;
      bytes memory dataURI = abi.encodePacked(
      '{',
          '"name": "Chicken #', tokenId.toString(), '",',
          '"attributes": [{"trait_type": "Level", "value": "', eggLevel[tokenId].toString(), '"}],',
          '"image": "',BASE_TOKEN_URI,'img/' , _chickenType.toString(),'/',eggLevel[tokenId].toString(), '.png",',
          '"animation_url": "',BASE_TOKEN_URI,'3d/' , _chickenType.toString(),'/',eggLevel[tokenId].toString(), '.glb"',
      '}'
      );
      return Base64.encode(dataURI);
  }

  function getChickenInfo(uint256 tokenId) public view returns (ChickenInfo memory) {
      string memory tokenInfo = this.tokenURI(tokenId);
      uint256 curEggLevel = this.eggLevel(tokenId);
      uint256 curNextTimeToLay = this.nextTimeToLay(tokenId);
      address curOwner = this.ownerOf(tokenId);

      return ChickenInfo(tokenId, tokenInfo, curEggLevel, curNextTimeToLay, curOwner);
  }

  function getChickenInfos(uint256[] calldata tokenIds) public view returns (ChickenInfo[] memory) {
    ChickenInfo[] memory chickenInfos = new ChickenInfo[](tokenIds.length);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      chickenInfos[i] = getChickenInfo(tokenIds[i]);
    }
    return chickenInfos;
  }

  function withdrawStoredEth(uint256 amount) public onlyParty {
    payable(partyAddress).transfer(amount);
  }

  function requestAirnodeWithdraw() external onlyParty {
    airnodeRrp.requestWithdrawal(airnode, sponsorWallet);
  }

  function _increaseLevel(uint256 tokenId, uint256 amountToIncrease) private {
    uint256 newLevel = eggLevel[tokenId] + amountToIncrease;
    require(newLevel <= MAX_LEVEL, "max level reached");
    emit LevelChanged(ownerOf(tokenId), tokenId, eggLevel[tokenId], newLevel);
    eggLevel[tokenId] = newLevel;
  }

  function _decreaseLevel(uint256 tokenId, uint256 amountToDecrease) private {
    uint256 newLevel = eggLevel[tokenId] - amountToDecrease;
    require(newLevel >= MIN_LEVEL, "min level reached");
    emit LevelChanged(ownerOf(tokenId), tokenId, eggLevel[tokenId], newLevel);
    eggLevel[tokenId] = newLevel;
  }

  function _birthChicken(address birthTo) private {
    lastTokenId++;
    _safeMint(birthTo, lastTokenId);
    eggLevel[lastTokenId] = 1;
  }

  // For receiving ETH
  receive() external payable {}


}