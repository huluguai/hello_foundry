// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract MyURINFTUpgradeable is Initializable, ERC721URIStorageUpgradeable, OwnableUpgradeable, UUPSUpgradeable
{
    uint256 private _nextTokenId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address initialOwner) public initializer {
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __Ownable_init(initialOwner);
        _nextTokenId = 1;
    }

    function mint(address to, string memory tokenUri_) external onlyOwner {
        uint256 tokenId = _nextTokenId;
        unchecked {
            _nextTokenId = tokenId + 1;
        }
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenUri_);
    }

    function currentTokenId() external view returns (uint256) {
        unchecked {
            return _nextTokenId - 1;
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
