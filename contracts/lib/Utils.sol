/*
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.28;

contract Utils {

    function _getAddress(
        address token_,
        bytes4 selector_
    ) internal view returns (address) {
        (bool success, bytes memory data) = token_.staticcall(
            abi.encodeWithSelector(selector_)
        );

        if (!success || data.length == 0) {
            return address(0);
        }

        if (data.length == 32) {
            return abi.decode(data, (address));
        }

        return address(0);
    }

    function _getTokens( address target_) internal view returns (address token0, address token1){
        token0 = _getAddress(target_, hex"0dfe1681");

        if (token0 != address(0)) {
            token1 = _getAddress(target_, hex"d21220a7");
        }

        return (token0, token1);
    }
}
