// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

interface IInfernalRiftBelow {

    function l2AddressForL1Collection(address _l1CollectionAddress) external view returns (address l2CollectionAddress_);

    function isDeployedOnL2(address _l1CollectionAddress) external view returns (bool isDeployed_);

    function claimRoyalties(
        address _collectionAddress,
        address _recipient,
        address[] calldata _tokens
    ) external;

}
