// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

import {LibOptimism} from "@openzeppelin/crosschain/optimism/LibOptimism.sol";

import {IInfernalPackage} from "./inferfaces/IInfernalPackage.sol";
import {ERC721Bridgable} from "./lib/ERC721Bridgable.sol";

contract InfernalRiftBelow is IInfernalPackage {

    address constant RELAYER_ADDRESS = 0x4200000000000000000000000000000000000007;
    address immutable INFERNAL_RIFT_ABOVE;

    error NotCrossDomainMessenger();
    error CrossChainSenderIsNotRiftAbove();

    mapping(address => address) public collectionLookup;

    constructor(address _INFERNAL_RIFT_ABOVE) {
        INFERNAL_RIFT_ABOVE = _INFERNAL_RIFT_ABOVE;
    }

    function thresholdCross(Package[] calldata packages) external {

        // Ensure call is coming from Infernal Rift Above
        if (msg.sender != RELAYER_ADDRESS) {
            revert NotCrossDomainMessenger();
        }
        if (LibOptimism.crossChainSender(msg.sender) != INFERNAL_RIFT_ABOVE) {
            revert CrossChainSenderIsNotRiftAbove();
        }

        // Go through and mint
        uint256 numPackages = packages.length;
        for (uint i; i < numPackages; ) {
            Package memory package = packages[i];
            address l2CollectionAddress = collectionLookup[package.collectionAddress];

            // If not yet deployed, deploy L2 contract
            if (l2CollectionAddress == 0) {
            }
            
            unchecked {
                ++i;
            }
        }
    }

}