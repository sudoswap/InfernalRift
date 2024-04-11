// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

import {LibOptimism} from "@openzeppelin/crosschain/optimism/LibOptimism.sol";
import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {IInfernalPackage} from "./interfaces/IInfernalPackage.sol";
import {ERC721Bridgable} from "./libs/ERC721Bridgable.sol";

contract InfernalRiftBelow is IInfernalPackage {

    address constant RELAYER_ADDRESS = 0x4200000000000000000000000000000000000007;
    address immutable INFERNAL_RIFT_ABOVE;
    address immutable ERC721_BRIDGABLE_IMPLEMENTATION;

    error NotCrossDomainMessenger();
    error CrossChainSenderIsNotRiftAbove();

    constructor(address _INFERNAL_RIFT_ABOVE, address _ERC721_BRIDGABLE_IMPLEMENTATION) {
        INFERNAL_RIFT_ABOVE = _INFERNAL_RIFT_ABOVE;
        ERC721_BRIDGABLE_IMPLEMENTATION = _ERC721_BRIDGABLE_IMPLEMENTATION;
    }

    function l2AddressForL1Collection(address l1CollectionAddress) public view returns (address l2CollectionAddress) {
        l2CollectionAddress = Clones.predictDeterministicAddress(
            ERC721_BRIDGABLE_IMPLEMENTATION, 
            bytes32(bytes20(l1CollectionAddress)));
    }

    function isDeployedOnL2(address l1CollectionAddress) public view returns (bool isDeployed) {
        isDeployed = l2AddressForL1Collection(l1CollectionAddress).code.length > 0;
    }

    function thresholdCross(Package[] calldata packages, address recipient) external {

        // Ensure call is coming from the cross chain messenger, and original msg.sender is Infernal Rift Above
        if (msg.sender != RELAYER_ADDRESS) {
            revert NotCrossDomainMessenger();
        }
        if (LibOptimism.crossChainSender(msg.sender) != INFERNAL_RIFT_ABOVE) {
            revert CrossChainSenderIsNotRiftAbove();
        }

        // Go through and mint (or transfer) NFTs to recipient
        uint256 numPackages = packages.length;
        for (uint i; i < numPackages; ) {
            Package memory package = packages[i];
            // If not yet deployed, deploy the L2 collection and set name/symbol/royalty
            address l1CollectionAddress = package.collectionAddress;
            address l2CollectionAddress = l2AddressForL1Collection(l1CollectionAddress);
            if (!isDeployedOnL2(l1CollectionAddress)) {
                Clones.cloneDeterministic(ERC721_BRIDGABLE_IMPLEMENTATION, bytes32(bytes20(l1CollectionAddress)));
                ERC721Bridgable(l2CollectionAddress).initialize(package.name, package.symbol, package.royaltyBps);
            }
            uint256 numIds = package.ids.length;
            for (uint j; j < numIds;) {
                uint id = package.ids[j];
                // If already escrowed in the bridge, then transfer to recipient
                if (ERC721Bridgable(l2CollectionAddress).ownerOf(id) == address(this)) {
                    ERC721Bridgable(l2CollectionAddress).transferFrom(address(this), recipient, id);
                }
                // Otherwise, set tokenURI and mint to recipient
                else {
                    ERC721Bridgable(l2CollectionAddress).setTokenURIAndMintFromRiftAbove(id, package.uris[j], recipient);
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    // Do the reverse (lock up, notify the L1)
    function returnFromThreshold(
    ) external {
    }

    // TODO: handle royalty collections

}