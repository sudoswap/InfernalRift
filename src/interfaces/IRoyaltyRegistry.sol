// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

interface IRoyaltyRegistry {
    /**
     * Returns royalty address location.  Returns the tokenAddress by default, or the override if it exists
     *
     * @param tokenAddress    - The token address you are looking up the royalty for
     */
    function getRoyaltyLookupAddress(address tokenAddress) external view returns (address);
}