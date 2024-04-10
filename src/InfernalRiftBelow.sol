// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

import {LibOptimism} from "@openzeppelin/crosschain/optimism/LibOptimism.sol";

import {IInfernalPackage} from "./IInfernalPackage.sol";

contract InfernalRiftBelow is IInfernalPackage {

    address constant RELAYER_ADDRESS = 0x4200000000000000000000000000000000000007;
    address immutable INFERNAL_RIFT_ABOVE;

    error InfidelDetected;
    error HeathenDetected;

    mapping(address => address) public collectionLookup;

    constructor(address _INFERNAL_RIFT_ABOVE) {
        INFERNAL_RIFT_ABOVE = _INFERNAL_RIFT_ABOVE;
    }

    function thresholdCross(Package[] calldata packages) external {

        // Ensure call is coming from Infernal Rift Above
        if (msg.sender != RELAYER_ADDRESS) {
            revert InfidelDetected();
        }
        if (LibOptimism.crossChainSender(msg.sender) != INFERNAL_RIFT_ABOVE) {
            revert HeathenDetected();
        }

        // Go through and mint
        uint256 numPackages = packages.length;
        for (uint i; i < numPackages; ) {
            
            // If undeployed, deploy and set metadata values
            // Otherwise, just mint

            unchecked {
                ++i;
            }
        }
    }

}