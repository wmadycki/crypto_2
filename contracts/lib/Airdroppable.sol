// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "../@openzeppelin/utils/Context.sol";

abstract contract Airdroppable is Context {
    struct AirdropInfo {
        address to;
        uint256 ethers;
    }

    /// @notice airdrop to multiple addresses
    /// @param airdropList list of addresses and amounts
    function airdrop(AirdropInfo[] memory airdropList) external {
        for (uint256 i = 0; i < airdropList.length; i++) {
            AirdropInfo memory adInfo = airdropList[i];
            _performAirdrop(adInfo.to, adInfo.ethers * 1e18);
        }
        _postAllAirdrops(_msgSender());
    }

    function _performAirdrop(address to_, uint256 wei_) internal virtual;

    function _postAllAirdrops(address from_) internal virtual;
}
