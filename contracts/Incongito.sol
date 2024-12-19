/*
 * @title $INCOGNITO - Earn Incentive (INC) tokens
 * @author Ra Murd <ramurd@pulselorian.com>
 * @notice https://pulselorian.com/
 * @notice https://t.me/ThePulselorian
 * @notice https://twitter.com/ThePulseLorian
 *
 * It's deflationary, burns portion of the fees, yields rest of the fees in INC tokens
 *
 *    (   (  (  (     (   (( (   .  (   (    (( (   ((
 *    )\  )\ )\ )\    )\ (\())\   . )\  )\   ))\)\  ))\
 *   ((_)((_)(_)(_)  ((_))(_)(_)   ((_)((_)(((_)_()((_)))
 *   | _ \ | | | |  / __| __| |   / _ \| _ \_ _|   \ \| |
 *   |  _/ |_| | |__\__ \ _|| |__| (_) |   /| || - | .  |
 *   |_|  \___/|____|___/___|____|\___/|_|_\___|_|_|_|\_|
 *
 * Tokenomics (initial fees):
 *          Buy      Sell     Transfer
 * Yield    4.50%    4.50%    0.00%
 * Burn     0.50%    0.50%    0.00%
 * BurnINC  (1/6th of Yield fee)
 *
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.28;

import "./@openzeppelin/access/Ownable.sol";
import "./@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./@uniswap/v2-core/interfaces/IUniswapV2Factory.sol";
import "./@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import "./@uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "./lib/Airdroppable.sol";
import "./lib/DSMath.sol";
import "./lib/ERC20.sol";
import "./lib/ERC20Permit.sol";
import "./lib/Utils.sol";

contract INCOGNITO is Airdroppable, DSMath, ERC20, ERC20Permit, Ownable, Utils {
    using SafeERC20 for IERC20;

    enum Fees {
        BurnFee,
        YieldFee,
        BurnINCFee,
        DevToll,
        LPToll,
        TknToll
    }

    struct WalletInfo {
        uint256 share;
        uint256 yieldDebt;
        uint256 yieldPaid;
    }

    IERC20 public immutable rwdInst =
    IERC20(0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d); // INC
    IUniswapV2Pair public plsV2LP;
    IUniswapV2Pair[] public lps;
    IUniswapV2Router02 public constant routerInst =
    IUniswapV2Router02(0x165C3410fC91EF562C50559f7d2289fEbed552d9); // V2 PulseX Router

    address private _devAddr1;
    address private _devAddr2;
    address private _lpAddr;
    address _tknAddr = 0xc1b4EfB8086a4a366712C851b1E3DB035eCC0532; // IncX mainnet

    address[] public wallets;

    bool private _swapping;
    bool public payoutEnabled = true;
    bool public swapEnabled = true;

    mapping(IUniswapV2Pair => uint24) public lpBips;
    mapping(address => WalletInfo) public walletInfo;
    mapping(address => bool) public isMyLP;
    mapping(address => bool) public noFee;
    mapping(address => bool) public noYield;
    mapping(address => uint256) public walletClaimTS;
    mapping(address => uint256) public walletIndex;

    uint16 private constant _BIPS = 10000;
    uint16 private constant _MAX_FEE = 500;
    uint16 private constant _MAX_TOLL = 10;
    uint16[] public fees = new uint16[](uint256(type(Fees).max) + 1);

    uint24 public lpFactor = 1000; // 0.033% - 1=100%, 100=1%, 1000=0.1%
    uint24 public maxGas = 200000;
    uint24 public minWaitSec = 43200; // 12 hours

    uint32 public currIndex;

    uint64 private constant _MULTIPLIER = 1e18;

    uint96 private constant _YIELDX = 1e27;
    uint96 public minYield = 483 * 1e13; // 0.00483 INC has 18 decimals

    uint256 private _feeDues;
    uint256 public launchBlock;
    uint256 public shareYieldRay;
    uint256 public totalPaid;
    uint256 public totalShares;
    uint256 public totalYield;
    uint256 public totalINCBurnt;

    constructor(
        string memory name,
        string memory symbol,
        address devAddr1_,
        address devAddr2_,
        address lpAddr_
    )
    ERC20(name, symbol)
    ERC20Permit(name)
    {
        _devAddr1 = devAddr1_;
        _devAddr2 = devAddr2_;
        _lpAddr = lpAddr_;
        address plsLPAddr = IUniswapV2Factory(routerInst.factory()).createPair(
            address(this),
            routerInst.WPLS()
        );

        plsV2LP = IUniswapV2Pair(plsLPAddr);
        isMyLP[plsLPAddr] = true;
        lps.push(plsV2LP);
        lpBips[plsV2LP] = 20000; // 2x

        fees[uint256(Fees.BurnFee)] = 50; // 0.5%
        fees[uint256(Fees.YieldFee)] = 450; // 4.5%
        fees[uint256(Fees.BurnINCFee)] = 75; // 1/6th
        fees[uint256(Fees.DevToll)] = 3; // 0.135%
        fees[uint256(Fees.LPToll)] = 6;
        fees[uint256(Fees.TknToll)] = 5;

        noFee[_msgSender()] = true;
        noFee[address(this)] = true;
        noFee[address(routerInst)] = true;

        noYield[address(0)] = true;
        noYield[address(0x369)] = true;
        noYield[address(this)] = true;
        noYield[plsLPAddr] = true;

        _mint(_msgSender(), 1e27); // 1 billion * 1e18
        _grantRole(GOVERN_ROLE, _msgSender());
    }

    receive() external payable {}

    function _buyTkn(uint256 tknAmt_) private {
        if (tknAmt_ == 0) return;
        address[] memory path = new address[](3);
        path[0] = address(rwdInst);
        path[1] = routerInst.WPLS();
        path[2] = _tknAddr;

        rwdInst.approve(address(routerInst), tknAmt_);
        try
        routerInst.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tknAmt_,
            0,
            path,
            address(0x369),
            block.timestamp
        )
        {} catch {}
    }

    function _calcFees(
        uint256 amt_,
        bool isFromLP_,
        bool isToLP_
    ) private view returns (uint256 burnFee, uint256 yieldFee) {
        if (isToLP_ || isFromLP_) {
            burnFee = (amt_ * fees[uint256(Fees.BurnFee)]) / _BIPS;
            yieldFee = (amt_ * fees[uint256(Fees.YieldFee)]) / _BIPS;
        }

        return (burnFee, yieldFee);
    }

    function _calcShares(
        address target_
    ) private view returns (uint256 shares) {
        uint256 lpShares;
        uint256 lpCount = lps.length;
        for (uint256 index = 0; index < lpCount; index++) {
            lpShares += ((lps[index].balanceOf(target_) * lpBips[lps[index]]) /
                _BIPS);
        }
        return balanceOf(target_) + lpShares;
    }

    function _checkIfMyLP(address target_) private returns (bool) {
        if (target_.code.length == 0) return false;
        if (!isMyLP[target_]) {
            (address token0, address token1) = Utils._getTokens(target_);
            if (token0 == address(this) || token1 == address(this)) {
                isMyLP[target_] = true;
                noYield[target_] = true;
            }
        }
        return isMyLP[target_];
    }

    function _disableYield(address wallet_) private {
        uint256 index = walletIndex[wallet_];
        uint256 walletCount = wallets.length;

        if (index < walletCount - 1) {
            address lastWallet = wallets[walletCount - 1];
            wallets[index] = lastWallet;
            walletIndex[lastWallet] = index;
        }

        wallets.pop();
        delete walletIndex[wallet_];
    }

    function _enableYield(address wallet_) private {
        uint256 index = wallets.length;
        walletIndex[wallet_] = index;
        wallets.push(wallet_);
    }

    function _getCummYield(uint256 share_) private view returns (uint256) {
        return (share_ * shareYieldRay) / _YIELDX;
    }

    function _isPayEligible(address wallet_) private view returns (bool) {
        return
            (walletClaimTS[wallet_] + minWaitSec) < block.timestamp &&
            getUnpaidYield(wallet_) > minYield;
    }

    function _payout(uint256 gas_) private {
        uint256 walletCount = wallets.length;

        if (walletCount == 0) {
            return;
        }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();
        uint256 iterations = 0;

        while (gasUsed < gas_ && iterations < walletCount) {
            if (currIndex >= walletCount) {
                currIndex = 0;
            }
            address wallet = wallets[currIndex];
            if (!noYield[wallet]) {
                bool paidYield = _setShare(wallet, _calcShares(wallet));

                if (!paidYield && _isPayEligible(wallet)) {
                    _payYield(wallet, true);
                }
            }
            currIndex++;
            iterations++;
            gasUsed += (gasLeft - gasleft());
            gasLeft = gasleft();
        }
    }

    function _payYield(address wallet_, bool flag_) private {
        WalletInfo storage walletI = walletInfo[wallet_];
        uint256 share = walletI.share;

        if (share == 0) {
            return;
        }

        uint256 amt = getUnpaidYield(wallet_);

        if (amt > 0) {
            if (flag_) {
                rwdInst.safeTransfer(wallet_, amt);
                walletI.yieldPaid += amt;
            } else {
                _feeDues += amt;
            }
            totalPaid = totalPaid + amt;
            walletClaimTS[wallet_] = block.timestamp;
            walletI.yieldDebt = _getCummYield(share);
        }
    }

    function _performAirdrop(address to_, uint256 wei_) internal override {
        super._transfer(_msgSender(), to_, wei_);
        if (!noYield[to_]) {
            _setShare(to_, _calcShares(to_));
        }
    }

    function _postAllAirdrops(address from_) internal override {
        if (!noYield[from_]) {
            _setShare(from_, _calcShares(_msgSender()));
        }
    }

    function _setShare(
        address wallet_,
        uint256 share_
    ) private returns (bool paidYield) {
        WalletInfo storage walletI = walletInfo[wallet_];
        uint256 shareOld = walletI.share;

        if (share_ != shareOld) {
            if (shareOld > 0) {
                _payYield(wallet_, (share_ > 0));
                paidYield = true;
            }

            if (share_ == 0) {
                _disableYield(wallet_);
            } else if (shareOld == 0) {
                _enableYield(wallet_);
            }

            totalShares = totalShares - shareOld + share_;
            walletI.share = share_;
            walletI.yieldDebt = _getCummYield(share_);
        }

        return paidYield;
    }

    function _swapTokens(uint256 tknAmt_) private {
        if (tknAmt_ == 0) return;

        uint256 fee = (tknAmt_ * fees[uint256(Fees.LPToll)]) / 100;
        if (_balances[address(this)] > fee) {
            _balances[address(this)] -= fee;
            _balances[_lpAddr] += fee;
            tknAmt_ -= fee;
        }

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = routerInst.WPLS();
        path[2] = address(rwdInst);

        uint256 balBefore = rwdInst.balanceOf(address(this));

        _approve(address(this), address(routerInst), tknAmt_);

        try
        routerInst.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tknAmt_,
            0,
            path,
            address(this),
            block.timestamp
        )
        {} catch {}

        uint256 newBal;
        uint256 balAfter = rwdInst.balanceOf(address(this));

        if (balAfter > balBefore) {
            newBal = balAfter - balBefore;
        }
        if (newBal > 0) {
            uint256 lpToll = (newBal * fees[uint256(Fees.LPToll)]) / 100;
            rwdInst.safeTransfer(_lpAddr, lpToll + _feeDues);
            _feeDues = 0;
            newBal -= lpToll;

            uint256 devToll = (newBal * fees[uint256(Fees.DevToll)]) / 100;
            rwdInst.safeTransfer(_devAddr1, devToll);
            rwdInst.safeTransfer(_devAddr2, devToll);
            newBal -= (devToll * 2);

            uint256 tknToll = (newBal * fees[uint256(Fees.TknToll)]) / 100;
            _buyTkn(tknToll);
            newBal -= tknToll;

            uint256 burnAmt = (fees[uint256(Fees.BurnINCFee)] * newBal) /
                            fees[uint256(Fees.YieldFee)];
            rwdInst.safeTransfer(address(0x369), burnAmt);
            newBal -= burnAmt;

            totalINCBurnt = totalINCBurnt + burnAmt;
            totalYield = totalYield + newBal;
            shareYieldRay = shareYieldRay + (_YIELDX * newBal) / totalShares;
        }
    }

    function _transfer(
        address from_,
        address to_,
        uint256 amt_
    ) internal override(ERC20) {
        bool isFromLP = _checkIfMyLP(from_);
        bool isToLP = _checkIfMyLP(to_);
        if (launchBlock == 0) {
            require(noFee[from_] || noFee[to_]);
            super._transfer(from_, to_, amt_);
        } else {
            uint256 yieldBal = balanceOf(address(this));
            uint256 swapAmt = getSwapSize(amt_);

            // Sell transaction when _swap is enabled and _swapping is not in progress
            if (
                swapEnabled &&
                (yieldBal >= swapAmt) &&
                !_swapping &&
                to_ == address(plsV2LP)
            ) {
                _swapping = true;
                _swapTokens(swapAmt);
                _swapping = false;
            }
            // uint256 plsRate = (_getXRate() * amt_) / _MULTIPLIER;
            if (!noFee[from_] && !noFee[to_]) {
                (uint256 burnFee, uint256 yieldFee) = _calcFees(
                    amt_,
                    isFromLP,
                    isToLP
                );

                if (burnFee > 0) {
                    super._transfer(from_, address(0x369), burnFee);
                    amt_ -= burnFee;
                }

                if (yieldFee > 0) {
                    super._transfer(from_, address(this), yieldFee);
                    amt_ -= yieldFee;
                }
            }
            super._transfer(from_, to_, amt_);
            if (payoutEnabled && !_swapping) {
                _payout(maxGas);
            }
            if (!noYield[from_]) {
                _setShare(from_, _calcShares(from_));
            }
            if (!noYield[to_]) {
                _setShare(to_, _calcShares(to_));
            }
        }
    }

    /// @notice Claim unpaid yield
    function claimYield() external {
        _payYield(_msgSender(), true);
    }

    /// @notice calculates number of tokens to convert
    /// @return swapSize number of tokens to swap
    function getSwapSize(uint256 amt_) private view returns (uint112 swapSize) {
        swapSize = uint112(balanceOf(address(plsV2LP)) / lpFactor);
        if (swapSize > amt_) {
            swapSize = uint112(amt_);
        }
        return swapSize;
    }

    /// @notice calculates LP Yield basis points
    /// @param lpPair_ LP Pair Instance (address)
    /// @return lpYieldBips number of tokens to swap
    function getLPYieldBips(
        IUniswapV2Pair lpPair_
    ) public view returns (uint24 lpYieldBips) {
        uint256 tknReserve;

        (uint256 reserve0, uint256 reserve1, ) = lpPair_.getReserves();
        if (lpPair_.token0() == address(this)) {
            tknReserve = reserve0;
        } else {
            tknReserve = reserve1;
        }
        if (tknReserve == 0) {
            return lpYieldBips;
        }

        uint256 totSup = lpPair_.totalSupply();
        lpYieldBips = uint24((tknReserve * _BIPS) / totSup); // 10000 = 100%

        return lpYieldBips;
    }

    /// @notice Retrieves unpaid yield
    /// @param wallet_ target address
    /// @return - unpaid yield for the given address
    function getUnpaidYield(address wallet_) public view returns (uint256) {
        WalletInfo storage walletI = walletInfo[wallet_];
        uint256 share = walletI.share;

        if (share == 0) {
            return 0;
        }

        uint256 cummYield = _getCummYield(share);
        uint256 walletYieldDebt = walletI.yieldDebt;

        if (cummYield <= walletYieldDebt) {
            return 0;
        }

        return cummYield - walletYieldDebt;
    }

    /// @notice Set the fees in basis points
    /// @param burnFee_ Burn fee
    /// @param yieldFee_ Yield fee
    /// @param burnINCFee_ Burn INC fee
    /// @param devToll_ Dev toll on conversion
    /// @param lpToll_ LP toll on conversion
    /// @param tknToll_ toll for tokens
    function setFees(
        uint16 burnFee_,
        uint16 yieldFee_,
        uint16 burnINCFee_,
        uint16 devToll_,
        uint16 lpToll_,
        uint16 tknToll_
    ) external onlyRole(GOVERN_ROLE) {
        require(
            burnFee_ <= _MAX_FEE &&
            yieldFee_ <= _MAX_FEE &&
            burnINCFee_ <= _MAX_FEE &&
            devToll_ <= _MAX_TOLL &&
            lpToll_ <= _MAX_TOLL &&
            tknToll_ <= _MAX_TOLL
        );

        fees[uint256(Fees.BurnFee)] = burnFee_;
        fees[uint256(Fees.YieldFee)] = yieldFee_;
        fees[uint256(Fees.BurnINCFee)] = burnINCFee_;
        fees[uint256(Fees.DevToll)] = devToll_;
        fees[uint256(Fees.LPToll)] = lpToll_;
        fees[uint256(Fees.TknToll)] = tknToll_;
    }

    /// @notice Set the Dev and growth wallet addresses
    /// @param devAddr1_ Dev1 address
    /// @param devAddr2_ Dev2 address
    /// @param lpAddr_ lp fee address
    function setTollAddrs(
        address devAddr1_,
        address devAddr2_,
        address lpAddr_
    ) external onlyRole(GOVERN_ROLE) {
        if (devAddr1_ != address(0)) {
            _devAddr1 = devAddr1_;
        }

        if (devAddr2_ != address(0)) {
            _devAddr2 = devAddr2_;
        }

        if (lpAddr_ != address(0)) {
            _lpAddr = lpAddr_;
        }
    }

    /// @notice Set the LP yield basis points
    /// @param lpPair_ lp address
    /// @param newLPYieldBips_ Basis points (10000 -> 100%)
    function setLPYieldBips(
        IUniswapV2Pair lpPair_,
        uint24 newLPYieldBips_
    ) external onlyRole(GOVERN_ROLE) {
        require(newLPYieldBips_ < 50000);

        if (newLPYieldBips_ == 0) {
            uint256 length = lps.length;
            for (uint256 lpi = 0; lpi < length; lpi++) {
                if (address(lps[lpi]) == address(lpPair_)) {
                    if (lpi < length - 1) {
                        lps[lpi] = lps[length - 1];
                        lps.pop();
                    } else {
                        lps.pop();
                    }
                }
            }
            lpBips[lpPair_] = 0;
        } else {
            uint256 length = lps.length;
            bool found = false;
            for (uint256 lpi = 0; lpi < length; lpi++) {
                if (address(lps[lpi]) == address(lpPair_)) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                lps.push(lpPair_);
            }
            lpBips[lpPair_] = newLPYieldBips_;
        }
    }

    /// @notice Enable/disable fees for addresses
    /// @dev For e.g. Routers need to excluded from fees
    /// @param wallet_ Target address
    /// @param flag_ Enable/disable flag
    function setNoFee(
        address wallet_,
        bool flag_
    ) external onlyRole(GOVERN_ROLE) {
        require(noFee[wallet_] != flag_);
        noFee[wallet_] = flag_;
    }

    /// @notice Enable/disable yield for addresses
    /// @dev For e.g. contracts may not be eligible
    /// @param wallet_ Target address
    /// @param flag_ Enable/disable flag
    function setNoYield(
        address wallet_,
        bool flag_
    ) external onlyRole(GOVERN_ROLE) {
        noYield[wallet_] = flag_;
        if (flag_) {
            _setShare(wallet_, 0);
        } else {
            _setShare(wallet_, _calcShares(wallet_));
        }
    }

    /// @notice Sets the payout policy for distribution of yield
    /// @param enabled_ Enable/disable flag
    /// @param minDurSec_ Duration between 2 payouts for a wallet
    /// @param minYield_ Minimum yield balance for payout
    /// @param gas_ Gas in gwei
    function setPayoutPolicy(
        bool enabled_,
        uint24 minDurSec_,
        uint80 minYield_,
        uint24 gas_
    ) external onlyRole(GOVERN_ROLE) {
        payoutEnabled = enabled_;
        minWaitSec = minDurSec_;
        minYield = minYield_;
        maxGas = gas_;
    }

    /// @notice Sets the swap paramenters
    /// @param swapEnabled_ Enable/disable swaps for conversion
    /// @param lpFactor_ New factor value 1000 = 0.1% 10000 = 0.01%
    function setSwapParams(
        bool swapEnabled_,
        uint24 lpFactor_
    ) external onlyRole(GOVERN_ROLE) {
        swapEnabled = swapEnabled_;
        if (swapEnabled_) {
            require(lpFactor_ >= 50 && lpFactor_ <= 200000);
            lpFactor = lpFactor_;
        }
    }

    /// @notice Sets the buy and burn token
    /// @param tknAddr_ token address
    function setToken(address tknAddr_) external onlyRole(GOVERN_ROLE) {
        _tknAddr = tknAddr_;
    }

    /// @notice start trading
    function startTrades() external onlyRole(GOVERN_ROLE) {
        require(launchBlock == 0);
        launchBlock = block.number;
    }
}
