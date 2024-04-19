// SPDX-License-Identifier: AGPL-3.0

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC2981} from "@openzeppelin/token/common/ERC2981.sol";

import {IInfernalPackage} from "./interfaces/IInfernalPackage.sol";
import {IInfernalRiftAbove} from "./interfaces/IInfernalRiftAbove.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";
import {IOptimismPortal} from "./interfaces/IOptimismPortal.sol";

import {InfernalRiftBelow} from "./InfernalRiftBelow.sol";

contract InfernalRiftAbove is IInfernalPackage, IInfernalRiftAbove {
    uint256 constant BPS_MULTIPLIER = 10000;

    address immutable PORTAL;
    address immutable L1_CROSS_DOMAIN_MESSENGER;
    address INFERNAL_RIFT_BELOW;

    error RiftBelowAlreadySet();
    error NotCrossDomainMessenger();
    error CrossChainSenderIsNotRiftBelow();

    constructor(address _PORTAL, address _L1_CROSS_DOMAIN_MESSENGER) {
        PORTAL = _PORTAL;
        L1_CROSS_DOMAIN_MESSENGER = _L1_CROSS_DOMAIN_MESSENGER;
    }

    function setInfernalRiftBelow(address a) external {
        if (INFERNAL_RIFT_BELOW != address(0)) {
            revert RiftBelowAlreadySet();
        }
        INFERNAL_RIFT_BELOW = a;
    }

    function crossTheThreshold(
        address[] calldata collectionAddresses,
        uint256[][] calldata idsToCross,
        address recipient,
        uint64 gasLimit
    ) external payable {
        // Set up payload
        uint256 numCollections = collectionAddresses.length;
        Package[] memory package = new Package[](numCollections);

        // Go through each collection, set values if needed
        for (uint256 i; i < numCollections;) {
            // Cache values needed
            uint256 numIds = idsToCross[i].length;
            address collectionAddress = collectionAddresses[i];

            // Go through each NFT, set its URI and escrow it
            string[] memory uris = new string[](numIds);
            for (uint256 j; j < numIds;) {
                uris[j] = IERC721Metadata(collectionAddress).tokenURI(idsToCross[i][j]);
                IERC721Metadata(collectionAddress).transferFrom(msg.sender, address(this), idsToCross[i][j]);
                unchecked {
                    ++j;
                }
            }

            // Grab royalty value from first ID
            uint96 royaltyBps;
            try ERC2981(collectionAddress).royaltyInfo(idsToCross[i][0], BPS_MULTIPLIER) returns (
                address, uint256 _royaltyAmount
            ) {
                royaltyBps = uint96(_royaltyAmount);
            } catch {
                // It's okay if it reverts (:
            }

            // Set up payload
            package[i] = Package({
                collectionAddress: collectionAddress,
                ids: idsToCross[i],
                uris: uris,
                royaltyBps: royaltyBps,
                name: IERC721Metadata(collectionAddress).name(),
                symbol: IERC721Metadata(collectionAddress).symbol()
            });
            unchecked {
                ++i;
            }
        }
        // Send package off to the portal
        IOptimismPortal(PORTAL).depositTransaction{value: msg.value}(
            INFERNAL_RIFT_BELOW,
            0,
            gasLimit,
            false,
            abi.encodeCall(InfernalRiftBelow.thresholdCross, (package, recipient))
        );
    }

    function returnFromTheThreshold(
        address[] calldata collectionAddresses,
        uint256[][] calldata idsToCross,
        address recipient
    ) external {
        // Validate caller is cross-chain and comes from rift below
        if (msg.sender != L1_CROSS_DOMAIN_MESSENGER) {
            revert NotCrossDomainMessenger();
        }
        if (ICrossDomainMessenger(msg.sender).xDomainMessageSender() != INFERNAL_RIFT_BELOW) {
            revert CrossChainSenderIsNotRiftBelow();
        }

        // Unlock NFTs to caller
        uint256 numCollections = collectionAddresses.length;
        for (uint256 i; i < numCollections;) {
            address l1CollectionAddress = collectionAddresses[i];
            uint256 numIds = idsToCross[i].length;
            for (uint256 j; j < numIds;) {
                IERC721Metadata(l1CollectionAddress).transferFrom(address(this), recipient, idsToCross[i][j]);
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }
}
