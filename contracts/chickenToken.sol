// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";


contract TrustToken is ERC20, ERC20Burnable, Ownable {
  uint256 public AMOUNT_FOR_PARTY = 60_000 ether; // for the party to deposit into LP pool
  
  IERC721 public validatorContract;

  modifier onlyValidatorContract() {
    require(address(validatorContract) != address(0), "chicken token is not set");
    require(address(validatorContract) == msg.sender, "caller is not the chicken token");
    _;
  }

  constructor(address _partyAddress) ERC20("Trust Token", "UBTT") Ownable(_partyAddress) {
    _mint(_partyAddress, AMOUNT_FOR_PARTY);
  }

  function setChickenAddress(IERC721 _henToken) public onlyOwner {
    chickenContract = _henToken;
  }

  function mintFor(address _to, uint256 _amount) public onlyChickenContract {
    _mint(_to, _amount);
  }

  function burnFor(address _from, uint256 _amount) public onlyChickenContract {
    require(balanceOf(_from) >= _amount, "not enough");
    _burn(_from, _amount);
  }

}