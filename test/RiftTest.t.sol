// SPDX-License-Identifier: AGPL-3.0

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */
/* solhint-disable no-unused-vars */
/* solhint-disable func-name-mixedcase */

pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {Test20} from './mocks/Test20.sol';
import {Test721} from "./mocks/Test721.sol";
import {Test721NoRoyalty} from './mocks/Test721NoRoyalty.sol';
import {MockPortalAndCrossDomainMessenger} from "./mocks/MockPortalAndCrossDomainMessenger.sol";
import {MockRoyaltyRegistry} from "./mocks/MockRoyaltyRegistry.sol";
import {ERC721Bridgable} from "../src/libs/ERC721Bridgable.sol";

import {InfernalRiftAbove} from "../src/InfernalRiftAbove.sol";
import {InfernalRiftBelow} from "../src/InfernalRiftBelow.sol";

contract RiftTest is Test {

    address constant ALICE = address(123456);

    Test721 l1NFT;
    MockPortalAndCrossDomainMessenger mockPortalAndMessenger;
    MockRoyaltyRegistry mockRoyaltyRegistry;
    ERC721Bridgable erc721Template;
    InfernalRiftAbove riftAbove;
    InfernalRiftBelow riftBelow;
    Test20 USDC;

    function setUp() public {

        /**
          - Deploy rift above
          - Deploy rift below
          - Deploy ERC721Brigable template and set with rift below
          - Set rift below to use ERC721Brigable
          - Set rift above to use rift below
          - Everything now immutable
         */

        USDC = new Test20('USDC', 'USDC', 18);
        l1NFT = new Test721();
        mockPortalAndMessenger = new MockPortalAndCrossDomainMessenger();
        mockRoyaltyRegistry = new MockRoyaltyRegistry();
        riftAbove = new InfernalRiftAbove(
            address(mockPortalAndMessenger),
            address(mockPortalAndMessenger),
            address(mockRoyaltyRegistry)
        );
        riftBelow = new InfernalRiftBelow(
            address(mockPortalAndMessenger), // pretend the portal *is* the relayer
            address(mockPortalAndMessenger),
            address(riftAbove)
        );
        erc721Template = new ERC721Bridgable("Test", "T721", address(riftBelow));
        riftBelow.initializeERC721Bridgable(address(erc721Template));
        riftAbove.setInfernalRiftBelow(address(riftBelow));
    }

    function test_basicSendOneNFT() public {
        vm.startPrank(ALICE);
        uint256[] memory ids = new uint256[](1);
        l1NFT.mint(ALICE, ids);
        l1NFT.setApprovalForAll(address(riftAbove), true);
        address[] memory collection = new address[](1);
        collection[0] = address(l1NFT);
        uint256[][] memory idList = new uint256[][](1);
        idList[0] = ids;
        mockPortalAndMessenger.setXDomainMessenger(address(riftAbove));
        riftAbove.crossTheThreshold(
            collection,
            idList,
            ALICE,
            0 // Skip gas limit checks for now
        );
    }

    function test_basicSendMultipleNfts() public {
        vm.startPrank(ALICE);

        // Build up a list of 3 collections, each containing a number of NFTs
        address[] memory collections = new address[](3);
        collections[0] = address(new Test721());
        collections[1] = address(new Test721());
        collections[2] = address(new Test721());

        uint[][] memory ids = new uint[][](collections.length);

        // Mint the NFT for each collection
        ids[0] = new uint[](5);
        ids[1] = new uint[](10);
        ids[2] = new uint[](1);

        // Mint our tokens to the test user and approve them for use by the portal
        for (uint i; i < ids.length; ++i) {
            Test721 nft = Test721(collections[i]);

            // Set our tokenIds
            for (uint j; j < ids[i].length; ++j) {
                ids[i][j] = j;
            }

            nft.mint(ALICE, ids[i]);
            nft.setApprovalForAll(address(riftAbove), true);
        }

        // Set our XDomain Messenger
        mockPortalAndMessenger.setXDomainMessenger(address(riftAbove));

        // Cross the threshold with multiple collections and tokens
        riftAbove.crossTheThreshold(collections, ids, ALICE, 0);
    }

    function test_CanBridgeNftBackAndForth() public {
        // This logic is tested in `test_basicSendOneNFT`
        _bridgeNft(address(this), address(l1NFT), 0);

        // Get our "L2" address
        Test721 l2NFT = Test721(riftBelow.l2AddressForL1Collection(address(l1NFT)));

        // Confirm our NFT holdings after the first transfer
        assertEq(l1NFT.ownerOf(0), address(riftAbove));
        assertEq(l2NFT.ownerOf(0), address(this));

        // Set up our return threshold parameters
        address[] memory collectionAddresses = new address[](1);
        collectionAddresses[0] = address(l2NFT);

        // Set up our tokenIds
        uint[][] memory tokenIds = new uint[][](1);
        tokenIds[0] = new uint[](1);
        tokenIds[0][0] = 0;

        // Approve the tokenIds on L2
        l2NFT.setApprovalForAll(address(riftBelow), true);

        // Set our domain messenger
        mockPortalAndMessenger.setXDomainMessenger(address(riftBelow));

        // Return the NFT
        riftBelow.returnFromThreshold(collectionAddresses, tokenIds, ALICE, 0);

        // Confirm that the NFT is back on the L1
        assertEq(l1NFT.ownerOf(0), ALICE);
        assertEq(l2NFT.ownerOf(0), address(riftBelow));

        // Transfer it to over to another user
        vm.prank(ALICE);
        l1NFT.transferFrom(ALICE, address(this), 0);

        // We will need to overwrite our collection addresses, but the ID will
        // stay the same. This time around we will send it to another user.
        collectionAddresses[0] = address(l1NFT);

        // Set our domain messenger
        mockPortalAndMessenger.setXDomainMessenger(address(riftAbove));

        riftAbove.crossTheThreshold(collectionAddresses, tokenIds, ALICE, 0);

        // Confirm the final holdings
        assertEq(l1NFT.ownerOf(0), address(riftAbove));
        assertEq(l2NFT.ownerOf(0), ALICE);
    }

    function test_CanClaimRoyalties() public {
        // Set the royalty information for the L1 contract
        l1NFT.setDefaultRoyalty(address(this), 1000);

        // Create an ERC721 that implements ERC2981 for royalties
        _bridgeNft(address(this), address(l1NFT), 0);

        // Get our "L2" address
        Test721 l2NFT = Test721(riftBelow.l2AddressForL1Collection(address(l1NFT)));

        // Add some royalties (10 ETH and 1000 USDC) onto the L2 contract
        deal(address(l2NFT), 10 ether);
        deal(address(USDC), address(l2NFT), 1000 ether);

        // Set up our tokens array to try and claim native ETH
        address[] memory tokens = new address[](2);
        tokens[0] = address(0);
        tokens[1] = address(USDC);

        // Capture the starting ETH of this caller
        uint startEthBalance = payable(address(this)).balance;

        // Make a claim call to an external recipient address
        riftAbove.claimRoyalties(address(l1NFT), ALICE, tokens, 0);

        // Confirm that tokens have been sent to ALICE and not the caller
        assertEq(payable(address(this)).balance, startEthBalance, 'Invalid caller ETH');
        assertEq(payable(ALICE).balance, 10 ether, 'Invalid ALICE ETH');

        assertEq(USDC.balanceOf(address(this)), 0, 'Invalid caller USDC');
        assertEq(USDC.balanceOf(ALICE), 1000 ether, 'Invalid ALICE USDC');
    }

    function test_CanClaimRoyaltiesWithMultipleTokenIdRoyaltyRecipients() public {
        /**
         * TODO: This could throw spanners as we want to have a global claim, but the
         * assignment method allows for individual overwrites without being able to
         * access the global directly.
         * 
         * How can we effectively determine the royalty caller that can access all
         * without just assuming `tokenId = 0`, or giving anyone access?
        */
    }

    function test_CannotClaimRoyaltiesOnInvalidContract() public {
        Test721NoRoyalty noRoyaltyNft = new Test721NoRoyalty();

        // Create an ERC721 that does not implement ERC2981
        _bridgeNft(address(this), address(noRoyaltyNft), 0);

        // Set up our tokens array to try and claim native ETH
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        // Try and claim royalties against the contract, even though it doesn't support
        // royalties in the expected way.
        vm.expectRevert(InfernalRiftAbove.CollectionNotERC2981Compliant.selector);
        riftAbove.claimRoyalties(address(noRoyaltyNft), ALICE, tokens, 0);
    }

    function test_CannotClaimRoyaltiesAsInvalidCaller() public {
        // Bridge our ERC721 onto the L2
        _bridgeNft(address(this), address(l1NFT), 0);

        // Set up our tokens array to try and claim native ETH
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                InfernalRiftAbove.CallerIsNotRoyaltiesReceiver.selector,
                ALICE, address(0)
            )
        );
        riftAbove.claimRoyalties(address(l1NFT), ALICE, tokens, 0);
        vm.stopPrank();
    }

    function test_CannotClaimRoyaltiesWithoutInfernalRift() public {
        // Bridge our ERC721 onto the L2
        _bridgeNft(address(this), address(l1NFT), 0);

        // Get our L2 address
        address l2NFT = riftBelow.l2AddressForL1Collection(address(l1NFT));

        // Set up our tokens array to try and claim native ETH
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        // Try and directly claim royalties
        vm.expectRevert(ERC721Bridgable.NotRiftBelow.selector);
        ERC721Bridgable(l2NFT).claimRoyalties(address(this), tokens);
    }

    function _bridgeNft(address _recipient, address _collection, uint _tokenId) internal {
        // Set our tokenId
        uint[] memory ids = new uint[](1);
        ids[0] = _tokenId;

        // Mint the token to our recipient
        Test721(_collection).mint(_recipient, ids);
        Test721(_collection).setApprovalForAll(address(riftAbove), true);
        
        // Register our collection and ID list
        address[] memory collections = new address[](1);
        collections[0] = _collection;

        uint256[][] memory idList = new uint256[][](1);
        idList[0] = ids;

        // Set our domain messenger
        mockPortalAndMessenger.setXDomainMessenger(address(riftAbove));

        // Cross the threshold!
        riftAbove.crossTheThreshold(collections, idList, address(this), 0);
    }

}