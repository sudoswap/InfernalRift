// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

import {LibOptimism} from "@openzeppelin/crosschain/optimism/LibOptimism.sol";

import {IInfernalPackage} from "./inferfaces/IInfernalPackage.sol";

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
            
            // If undeployed, deploy and set metadata values
            // Otherwise, if held by the rift, just send to the new caller

            unchecked {
                ++i;
            }
        }
    }

}