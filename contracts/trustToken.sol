// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol"; // Added missing import

contract TrustToken is ERC20, Ownable, ERC20Burnable {
    ERC721 public validatorContract;
    address public _dao; // Removed "private"

    constructor(address initialOwner, address _fixedMinter)
    ERC20("Trust Token", "UBTT")
    Ownable(initialOwner)
    {
        _dao = _fixedMinter;
    }   

    modifier onlyValidatorContract() {
        require(msg.sender == address(validatorContract), "Not validator contract");
        _;
    }

    modifier onlyDAO() { // Reintroduced the onlyDAO modifier
        require(msg.sender == _dao, "Not the DAO address");
        _;
    }

    function setDAO(address dao) external onlyOwner {
        _dao = dao;
    }

    function setValidatorContract(address validator) external onlyOwner {
        validatorContract = ERC721(validator);
    }

    function mintByValidator(address to, uint256 amount) public onlyValidatorContract {
        _mint(to, amount);
    }

    function mintByDAO(address to, uint256 amount) public onlyDAO {
        _mint(to, amount);
    }

    // Function not included in the original response, but kept for reference
    // function mintByFixedMinter(address to, uint256 amount) public onlyFixedMinter {
    //   _mint(to, amount);
    // }

    function burnFor(address _from, uint256 amount) public payable onlyValidatorContract {
        require(balanceOf(_from) >= amount, "Insufficient balance");
        _burn(_from, amount);
    }
}
