// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

interface IInfernalRiftAbove {
    function returnFromTheThreshold(
        address[] calldata collectionAddresses,
        uint256[][] calldata idsToCross,
        address recipient
    ) external;
}
