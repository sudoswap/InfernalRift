// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IInfernalPackage {
    struct Package {
        address collectionAddress;
        uint96 royaltyBps;
        uint256[] ids;
        string[] uris;
        string name;
        string symbol;
    }
}