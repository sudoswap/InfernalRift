// SPDX-License-Identifier: AGPL-3.0-or-later

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */
/* solhint-disable no-unused-vars */
/* solhint-disable func-name-mixedcase */

pragma solidity ^0.8.0;

import {IRoyaltyRegistry} from "../../src/interfaces/IRoyaltyRegistry.sol";

contract MockRoyaltyRegistry is IRoyaltyRegistry {
    function getRoyaltyLookupAddress(address tokenAddress) external pure returns (address) {
        return tokenAddress;
    }
}