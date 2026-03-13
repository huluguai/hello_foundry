// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MyURINFT is ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;

    constructor() ERC721("MyURINFT", "MUN") Ownable(msg.sender) {
        _nextTokenId = 1;
    }

    /// @notice 只有 owner 可以铸造，并设置 tokenURI
    /// @param to 接收 NFT 的地址
    /// @param tokenUri_ 元数据地址，一般是 ipfs:// 或 https:// 链接
    function mint(address to, string memory tokenUri_) external onlyOwner {
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenUri_);
    }

    function currentTokenId() external view returns (uint256) {
        return _nextTokenId - 1;
    }
}