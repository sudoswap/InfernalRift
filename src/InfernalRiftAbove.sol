// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

import {IERC721Metadata} from "@openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC2981} from "@openzeppelin/token/common/ERC2981.sol";
import {IERC2981} from "@openzeppelin/interfaces/IERC2981.sol";

import {IInfernalPackage} from "./interfaces/IInfernalPackage.sol";
import {IRoyaltyRegistry} from "./interfaces/IRoyaltyRegistry.sol";
import {IInfernalRiftAbove} from "./interfaces/IInfernalRiftAbove.sol";
import {IInfernalRiftBelow} from "./interfaces/IInfernalRiftBelow.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";
import {IOptimismPortal} from "./interfaces/IOptimismPortal.sol";

import {InfernalRiftBelow} from "./InfernalRiftBelow.sol";


contract InfernalRiftAbove is IInfernalPackage, IInfernalRiftAbove {
    uint constant internal BPS_MULTIPLIER = 10000;

    IOptimismPortal immutable public PORTAL;
    address immutable public L1_CROSS_DOMAIN_MESSENGER;
    IRoyaltyRegistry immutable public ROYALTY_REGISTRY;
    address public INFERNAL_RIFT_BELOW;

    error RiftBelowAlreadySet();
    error NotCrossDomainMessenger();
    error CrossChainSenderIsNotRiftBelow();
    error CollectionNotERC2981Compliant();
    error CallerIsNotRoyaltiesReceiver(address _caller, address _receiver);

    constructor(address _PORTAL, address _L1_CROSS_DOMAIN_MESSENGER, address _ROYALTY_REGISTRY) {
        PORTAL = IOptimismPortal(_PORTAL);
        L1_CROSS_DOMAIN_MESSENGER = _L1_CROSS_DOMAIN_MESSENGER;
        ROYALTY_REGISTRY = IRoyaltyRegistry(_ROYALTY_REGISTRY);
    }

    /**
     * Allows the {InfernalRiftBelow} contract to be set.
     * 
     * @dev This contract address cannot be updated if a non-zero address already set.
     * 
     * @param _infernalRiftBelow Address of the {InfernalRiftBelow} contract
     */
    function setInfernalRiftBelow(address _infernalRiftBelow) external {
        if (INFERNAL_RIFT_BELOW != address(0)) {
            revert RiftBelowAlreadySet();
        }

        INFERNAL_RIFT_BELOW = _infernalRiftBelow;
    }

    /**
     * Sends ERC721 tokens from the L1 chain to L2.
     * 
     * @param collectionAddresses Addresses of collections returning from L2
     * @param idsToCross Array of tokenIds, with the first iterator referring to collectionAddress
     * @param recipient The recipient of the tokens on L2
     * @param gasLimit The maximum amount of gas to spend in transaction
     */
    function crossTheThreshold(
        address[] calldata collectionAddresses,
        uint[][] calldata idsToCross,
        address recipient,
        uint64 gasLimit
    ) external payable {
        // Set up payload
        uint numCollections = collectionAddresses.length;
        Package[] memory package = new Package[](numCollections);

        // Cache variables ahead of our loops
        uint numIds;
        address collectionAddress;
        string[] memory uris;
        IERC721Metadata erc721;

        // Go through each collection, set values if needed
        for (uint i; i < numCollections; ++i) {
            // Cache values needed
            numIds = idsToCross[i].length;
            collectionAddress = collectionAddresses[i];

            erc721 = IERC721Metadata(collectionAddress);

            // Go through each NFT, set its URI and escrow it
            uris = new string[](numIds);
            for (uint j; j < numIds; ++j) {
                uris[j] = erc721.tokenURI(idsToCross[i][j]);
                erc721.transferFrom(msg.sender, address(this), idsToCross[i][j]);
            }

            // Grab royalty value from first ID
            uint96 royaltyBps;
            try ERC2981(
                ROYALTY_REGISTRY.getRoyaltyLookupAddress(collectionAddress)
            ).royaltyInfo(idsToCross[i][0], BPS_MULTIPLIER) returns (address, uint _royaltyAmount) {
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
                name: erc721.name(),
                symbol: erc721.symbol()
            });
        }

        // Send package off to the portal
        PORTAL.depositTransaction{value: msg.value}(
            INFERNAL_RIFT_BELOW,
            0,
            gasLimit,
            false,
            abi.encodeCall(InfernalRiftBelow.thresholdCross, (package, recipient))
        );
    }

    /**
     * Handle NFTs being transferred back to the L1 from the L2.
     * 
     * @dev The NFTs must be stored in this contract to redistribute back on L1
     * 
     * @param collectionAddresses Addresses of collections returning from L2
     * @param idsToCross Array of tokenIds, with the first iterator referring to collectionAddress
     * @param recipient The recipient of the tokens
     */
    function returnFromTheThreshold(
        address[] calldata collectionAddresses,
        uint[][] calldata idsToCross,
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
        uint numCollections = collectionAddresses.length;

        IERC721Metadata erc721;
        uint numIds;

        for (uint i; i < numCollections; ++i) {
            erc721 = IERC721Metadata(collectionAddresses[i]);
            numIds = idsToCross[i].length;

            for (uint j; j < numIds; ++j) {
                erc721.transferFrom(address(this), recipient, idsToCross[i][j]);
            }
        }
    }

    /**
     * If the contract address on L1 implements `EIP-2981`, then we can allow the recipient
     * of the L1 royalties make the claim against the L2 equivalent.
     * 
     * @param _collectionAddress The address of the L1 collection
     * @param _recipient The L2 recipient of the claim
     * @param _tokens Addresses of tokens to claim
     * @param _gasLimit The limit of gas to send
     */
    function claimRoyalties(address _collectionAddress, address _recipient, address[] calldata _tokens, uint32 _gasLimit) external {
        // We then need to make sure that the L1 contract supports royalties via EIP-2981
        if (!IERC2981(_collectionAddress).supportsInterface(type(IERC2981).interfaceId)) revert CollectionNotERC2981Compliant();
        
        // We can now pull the royalty information from the L1 to confirm that the caller
        // is the receiver of the royalties. We can't actually pull in the default royalty
        // provider so instead we just use token0.
        (address receiver,) = IERC2981(_collectionAddress).royaltyInfo(0, 0);

        // Check that the receiver of royalties is making this call
        if (receiver != msg.sender) revert CallerIsNotRoyaltiesReceiver(msg.sender, receiver);

        // Make our call to the L2 that will pull tokens from the contract
        ICrossDomainMessenger(L1_CROSS_DOMAIN_MESSENGER).sendMessage(
            INFERNAL_RIFT_BELOW,
            abi.encodeCall(
                IInfernalRiftBelow.claimRoyalties,
                (_collectionAddress, _recipient, _tokens)
            ),
            _gasLimit
        );
    }

}
