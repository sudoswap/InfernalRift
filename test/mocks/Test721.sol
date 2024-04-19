// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC721Royalty, ERC721} from "@openzeppelin/token/ERC721/extensions/ERC721Royalty.sol";
import {Strings} from "@openzeppelin/utils/Strings.sol";

contract Test721 is ERC721Royalty {

    constructor() ERC721("Test721", "T721") {}

    function mint(address to, uint256[] calldata ids) external {
        for (uint i; i < ids.length; ++i) {
            _mint(to, ids[i]);
        }
    }

    function tokenURI(uint256 id) public view override returns (string memory uri) {
        uri = string.concat("foo", Strings.toString(id));
    }
}
