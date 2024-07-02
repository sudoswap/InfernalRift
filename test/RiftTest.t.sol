// SPDX-License-Identifier: AGPL-3.0

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */
/* solhint-disable no-unused-vars */
/* solhint-disable func-name-mixedcase */

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Test721} from "./mocks/Test721.sol";
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

    function setUp() public {

        /**
          - Deploy rift above
          - Deploy rift below
          - Deploy ERC721Brigable template and set with rift below
          - Set rift below to use ERC721Brigable
          - Set rift above to use rift below
          - Everything now immutable
         */

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

}