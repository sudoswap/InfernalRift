// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

/// @dev This interface is used on L2, we can afford to spend a bit more gas on safety guarantees

interface ICrossDomainMessenger {
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable;
    function xDomainMessageSender() external view returns (address);
}
