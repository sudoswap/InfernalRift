// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

import {Clones} from "@openzeppelin/proxy/Clones.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

import {IInfernalPackage} from "./interfaces/IInfernalPackage.sol";
import {IInfernalRiftAbove} from "./interfaces/IInfernalRiftAbove.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";
import {ERC721Bridgable} from "./libs/ERC721Bridgable.sol";

contract InfernalRiftBelow is IInfernalPackage {
    address immutable RELAYER_ADDRESS;
    address immutable L2_CROSS_DOMAIN_MESSENGER;
    address immutable INFERNAL_RIFT_ABOVE;
    address immutable ERC721_BRIDGABLE_IMPLEMENTATION;

    error NotCrossDomainMessenger();
    error CrossChainSenderIsNotRiftAbove();
    error L1CollectionDoesNotExist();

    mapping(address => address) public l1AddressForL2Collection;

    constructor(
        address _RELAYER_ADDRESS,
        address _L2_CROSS_DOMAIN_MESSENGER,
        address _INFERNAL_RIFT_ABOVE,
        address _ERC721_BRIDGABLE_IMPLEMENTATION
    ) {
        RELAYER_ADDRESS = _RELAYER_ADDRESS;
        L2_CROSS_DOMAIN_MESSENGER = _L2_CROSS_DOMAIN_MESSENGER;
        INFERNAL_RIFT_ABOVE = _INFERNAL_RIFT_ABOVE;
        ERC721_BRIDGABLE_IMPLEMENTATION = _ERC721_BRIDGABLE_IMPLEMENTATION;
    }

    function l2AddressForL1Collection(address l1CollectionAddress) public view returns (address l2CollectionAddress) {
        l2CollectionAddress =
            Clones.predictDeterministicAddress(ERC721_BRIDGABLE_IMPLEMENTATION, bytes32(bytes20(l1CollectionAddress)));
    }

    function isDeployedOnL2(address l1CollectionAddress) public view returns (bool isDeployed) {
        isDeployed = l2AddressForL1Collection(l1CollectionAddress).code.length > 0;
    }

    function thresholdCross(Package[] calldata packages, address recipient) external {
        // Ensure call is coming from the cross chain messenger, and original msg.sender is Infernal Rift Above
        if (msg.sender != RELAYER_ADDRESS) {
            revert NotCrossDomainMessenger();
        }
        if (ICrossDomainMessenger(msg.sender).xDomainMessageSender() != INFERNAL_RIFT_ABOVE) {
            revert CrossChainSenderIsNotRiftAbove();
        }

        // Go through and mint (or transfer) NFTs to recipient
        uint256 numPackages = packages.length;
        for (uint256 i; i < numPackages;) {
            Package memory package = packages[i];
            // If not yet deployed, deploy the L2 collection and set name/symbol/royalty
            address l1CollectionAddress = package.collectionAddress;
            address l2CollectionAddress = l2AddressForL1Collection(l1CollectionAddress);
            if (!isDeployedOnL2(l1CollectionAddress)) {
                Clones.cloneDeterministic(ERC721_BRIDGABLE_IMPLEMENTATION, bytes32(bytes20(l1CollectionAddress)));
                ERC721Bridgable(l2CollectionAddress).initialize(package.name, package.symbol, package.royaltyBps);
                // Set the reverse mapping
                l1AddressForL2Collection[l1CollectionAddress] = l2CollectionAddress;
            }
            uint256 numIds = package.ids.length;
            for (uint256 j; j < numIds;) {
                uint256 id = package.ids[j];
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
        address[] calldata collectionAddresses,
        uint256[][] calldata idsToCross,
        address recipient,
        uint32 gasLimit
    ) external {
        uint256 numCollections = collectionAddresses.length;
        address[] memory l1CollectionAddresses = new address[](numCollections);
        for (uint256 i; i < numCollections;) {
            address l2CollectionAddress = collectionAddresses[i];
            uint256 numIds = idsToCross[i].length;
            for (uint256 j; j < numIds;) {
                IERC721(l2CollectionAddress).transferFrom(msg.sender, address(this), idsToCross[i][j]);
                unchecked {
                    ++j;
                }
            }
            // Look up the L1 collection address
            address l1CollectionAddress = l1AddressForL2Collection[l2CollectionAddress];

            // Revert if L1 collection does not exist
            // (e.g. if a non bridged NFT is trying to bridge)
            if (l1CollectionAddress == address(0)) {
                revert L1CollectionDoesNotExist();
            }

            l1CollectionAddresses[i] = l1CollectionAddress;
            unchecked {
                ++i;
            }
        }
        ICrossDomainMessenger(L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            INFERNAL_RIFT_ABOVE,
            abi.encodeCall(IInfernalRiftAbove.returnFromTheThreshold, (l1CollectionAddresses, idsToCross, recipient)),
            gasLimit
        );
    }

    // TODO: handle royalty collections
}
