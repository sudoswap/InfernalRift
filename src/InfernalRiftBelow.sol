// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.26;

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */

import {Clones} from "@openzeppelin/proxy/Clones.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

import {IInfernalPackage} from "./interfaces/IInfernalPackage.sol";
import {IInfernalRiftAbove} from "./interfaces/IInfernalRiftAbove.sol";
import {IInfernalRiftBelow} from "./interfaces/IInfernalRiftBelow.sol";
import {ICrossDomainMessenger} from "./interfaces/ICrossDomainMessenger.sol";

import {ERC721Bridgable} from "./libs/ERC721Bridgable.sol";


contract InfernalRiftBelow is IInfernalPackage, IInfernalRiftBelow {

    address immutable public RELAYER_ADDRESS;
    ICrossDomainMessenger immutable public L2_CROSS_DOMAIN_MESSENGER;
    address immutable public INFERNAL_RIFT_ABOVE;

    error TemplateAlreadySet();
    error NotRelayerCaller();
    error CrossChainSenderIsNotRiftAbove();
    error L1CollectionDoesNotExist();

    /// Stores mapping of L1 addresses for their corresponding L2 addresses
    mapping(address _l2TokenAddress => address _l1TokenAddress) public l1AddressForL2Collection;

    /// The deployed contract address of the ERC721Bridgable used for implementations 
    address public ERC721_BRIDGABLE_IMPLEMENTATION;

    constructor(
        address _RELAYER_ADDRESS,
        address _L2_CROSS_DOMAIN_MESSENGER,
        address _INFERNAL_RIFT_ABOVE
    ) {
        RELAYER_ADDRESS = _RELAYER_ADDRESS;
        L2_CROSS_DOMAIN_MESSENGER = ICrossDomainMessenger(_L2_CROSS_DOMAIN_MESSENGER);
        INFERNAL_RIFT_ABOVE = _INFERNAL_RIFT_ABOVE;
    }

    /**
     * Provides the L2 address for the L1 collection. This does not require that the collection
     * to actually be deployed, but only provides the address that it either does, or will, have.
     * 
     * @param l1CollectionAddress The L1 collection address
     * 
     * @return l2CollectionAddress The corresponding L2 collection address
     */
    function l2AddressForL1Collection(address l1CollectionAddress) public view returns (address l2CollectionAddress) {
        l2CollectionAddress = Clones.predictDeterministicAddress(
            ERC721_BRIDGABLE_IMPLEMENTATION,
            bytes32(bytes20(l1CollectionAddress))
        );
    }

    /**
     * Checks if the specified L1 address has code deployed to it on the L2.
     * 
     * @param l1CollectionAddress The L1 collection address
     * 
     * @return isDeployed If the determined L2 address has code deployed to it
     */
    function isDeployedOnL2(address l1CollectionAddress) public view returns (bool isDeployed) {
        isDeployed = l2AddressForL1Collection(l1CollectionAddress).code.length > 0;
    }

    /**
     * Allows the {ERC721Bridgable} implementation to be set.
     * 
     * @dev If this value has already been set, then it cannot be updated.
     * 
     * @param _erc721Bridgable Address of the {ERC721Bridgable} implementation
     */
    function initializeERC721Bridgable(address _erc721Bridgable) external {
        if (ERC721_BRIDGABLE_IMPLEMENTATION != address(0)) {
            revert TemplateAlreadySet();
        }

        ERC721_BRIDGABLE_IMPLEMENTATION = _erc721Bridgable;
    }

    /**
     * Handles `crossTheThreshold` calls from {InfernalRiftAbove} to distribute migrated
     * tokens across the L2 to the specified recipient.
     * 
     * @param packages Information for NFTs to distribute
     * @param recipient The L2 recipient address
     */
    function thresholdCross(Package[] calldata packages, address recipient) external {
        // Ensure call is coming from the cross chain messenger
        if (msg.sender != RELAYER_ADDRESS) {
            revert NotRelayerCaller();
        }

        // Ensure original msg.sender is {InfernalRiftAbove}
        if (ICrossDomainMessenger(msg.sender).xDomainMessageSender() != INFERNAL_RIFT_ABOVE) {
            revert CrossChainSenderIsNotRiftAbove();
        }

        // Go through and mint (or transfer) NFTs to recipient
        uint numPackages = packages.length;
        for (uint i; i < numPackages; ++i) {
            Package memory package = packages[i];

            address l1CollectionAddress = package.collectionAddress;
            address l2CollectionAddress = l2AddressForL1Collection(l1CollectionAddress);

            ERC721Bridgable l2Collection;

            // If not yet deployed, deploy the L2 collection and set name/symbol/royalty
            if (!isDeployedOnL2(l1CollectionAddress)) {
                Clones.cloneDeterministic(ERC721_BRIDGABLE_IMPLEMENTATION, bytes32(bytes20(l1CollectionAddress)));

                l2Collection = ERC721Bridgable(l2CollectionAddress);
                l2Collection.initialize(package.name, package.symbol, package.royaltyBps);

                // Set the reverse mapping
                l1AddressForL2Collection[l2CollectionAddress] = l1CollectionAddress;
            }
            // Otherwise, our collection already exists and we can reference it directly
            else {
                l2Collection = ERC721Bridgable(l2CollectionAddress);
            }

            // Iterate over our tokenIds to transfer them to the recipient
            uint numIds = package.ids.length;
            uint id;

            for (uint j; j < numIds; ++j) {
                id = package.ids[j];

                // If already escrowed in the bridge, then transfer to recipient
                if (l2Collection.ownerOf(id) == address(this)) {
                    l2Collection.transferFrom(address(this), recipient, id);
                }
                // Otherwise, set tokenURI and mint to recipient
                else {
                    l2Collection.setTokenURIAndMintFromRiftAbove(id, package.uris[j], recipient);
                }
            }
        }
    }

    /**
     * Handles the bridging of tokens from the L2 back to L1.
     * 
     * @param collectionAddresses The L2 collection addresses to bridge
     * @param idsToCross The tokenIds for respective collections to bridge
     * @param recipient The L1 recipient of the bridged tokens
     * @param gasLimit The limit of gas to send
     */
    function returnFromThreshold(
        address[] calldata collectionAddresses,
        uint[][] calldata idsToCross,
        address recipient,
        uint32 gasLimit
    ) external {
        uint numCollections = collectionAddresses.length;
        address[] memory l1CollectionAddresses = new address[](numCollections);
        address l1CollectionAddress;
        IERC721 l2Collection;
        uint numIds;

        // Iterate over our collections
        for (uint i; i < numCollections; ++i) {
            l2Collection = IERC721(collectionAddresses[i]);
            numIds = idsToCross[i].length;

            // Iterate over the specified NFTs to pull them from the user and store
            // within this contract for potential future bridging use.
            for (uint j; j < numIds; ++j) {
                l2Collection.transferFrom(msg.sender, address(this), idsToCross[i][j]);
            }

            // Look up the L1 collection address
            l1CollectionAddress = l1AddressForL2Collection[address(l2Collection)];

            // Revert if L1 collection does not exist
            if (l1CollectionAddress == address(0)) revert L1CollectionDoesNotExist();
            l1CollectionAddresses[i] = l1CollectionAddress;
        }

        // Send our message to {InfernalRiftAbove} 
        L2_CROSS_DOMAIN_MESSENGER.sendMessage(
            INFERNAL_RIFT_ABOVE,
            abi.encodeCall(
                IInfernalRiftAbove.returnFromTheThreshold,
                (l1CollectionAddresses, idsToCross, recipient)
            ),
            gasLimit
        );
    }

    /**
     * Routes a royalty claim call to the L2 ERC721, as this contract will be the owner of
     * the royalties.
     * 
     * @dev This assumes that {InfernalRiftAbove} has already validated the initial caller
     * as the royalty holder of the token.
     * 
     * @param _collectionAddress The L1 collection address to claim royalties for
     * @param _recipient The L2 recipient of the royalties
     * @param _tokens Array of token addresses to claim
     */
    function claimRoyalties(address _collectionAddress, address _recipient, address[] calldata _tokens) public {
        // Ensure that our message is sent from the L1 domain messenger
        if (ICrossDomainMessenger(msg.sender).xDomainMessageSender() != INFERNAL_RIFT_ABOVE) {
            revert CrossChainSenderIsNotRiftAbove();
        }

        // Get our L2 address from the L1
        if (!isDeployedOnL2(_collectionAddress)) revert L1CollectionDoesNotExist();

        // Call our ERC721Bridgable contract as the owner to claim royalties to the recipient
        ERC721Bridgable(l2AddressForL1Collection(_collectionAddress)).claimRoyalties(_recipient, _tokens);
    }

}
