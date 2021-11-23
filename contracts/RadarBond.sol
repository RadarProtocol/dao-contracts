// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IRadarBondsTreasury.sol";
import "./interfaces/IRadarBond.sol";
import "./interfaces/IRadarStaking.sol";
import "./external/IUniswapV2Pair.sol";
import "./external/IERC20.sol";

contract RadarBond is IRadarBond {

    mapping(address => BondInfo) private bonds;
    mapping(address => uint256) flashProtection;
    mapping(address => bool) trustedOrigins;
    BondTerms private terms;

    address private TREASURY;
    address private STAKING;
    address private immutable PAYOUT_ASSET;
    address private immutable BOND_ASSET;

    uint256 private constant DISCOUNT_DIVISOR = 10000;

    modifier onlyManager {
        require(msg.sender == getManager(), "Unauthorized");
        _;
    }

    modifier flashLocked {
        if (!trustedOrigins[tx.origin]) {
            require(block.number > flashProtection[tx.origin], "Flash Protection");
        }
        _;
        flashProtection[tx.origin] = block.number;
    }

    constructor (
        address _treasury,
        address _payoutAsset,
        address _bondAsset,
        address _staking,
        uint256 _depositLimit, // bondAsset is LP token, so this limit max reward of payout token per user
        uint256 _vestingTime,
        uint256 _bondDiscount,
        uint256 _minPrice
    ) {
        TREASURY = _treasury;
        PAYOUT_ASSET = _payoutAsset;
        BOND_ASSET = _bondAsset;
        STAKING = _staking;
        terms = BondTerms({
            bondPayoutLimit: _depositLimit,
            vestingTime: _vestingTime,
            bondDiscount: _bondDiscount,
            minPrice: _minPrice
        });
    }

    // Manager functions
    function changeTerms(
        uint256 _depositLimit, // bondAsset is LP token, so this limit max reward of payout token per user
        uint256 _vestingTime,
        uint256 _bondDiscount,
        uint256 _minPrice
    ) external onlyManager {
        terms = BondTerms({
            bondPayoutLimit: _depositLimit,
            vestingTime: _vestingTime,
            bondDiscount: _bondDiscount,
            minPrice: _minPrice
        });
    }

    function changeTreasury(address _newTreasury) external onlyManager {
        TREASURY = _newTreasury;
    }

    function changeStaking(address _newStaking) external onlyManager {
        STAKING = _newStaking;
    }

    function setTrustedOrigin(address _origin, bool _status) external onlyManager {
        trustedOrigins[_origin] = _status;
    }

    // Bond functions
    function bond(uint256 _amount, uint256 _minReward) external override flashLocked {
        // TODO: Implement

        // Slippage minReward
        // Check reward is smaller than reward limit
        // Check minPrice when calculating payout asset from bond asset
        // If lower than minPrice, fail
    }

    function redeem(bool _stake) external override flashLocked {
        // TODO: Implement
    }

    // Internal functions
    // TODO: IMPORTANT!!! TEST
    function _rewardToLPBondAsset(uint256 _payoutAssetAmount) internal view returns (uint256) {
        
        uint256 _value = (_payoutAssetAmount * DISCOUNT_DIVISOR) / (terms.bondDiscount + DISCOUNT_DIVISOR);
        _value = _value / 2;

        (uint256 _reserve0, uint256 _reserve1, ) = IUniswapV2Pair(BOND_ASSET).getReserves();
        uint256 _totalSupply = IUniswapV2Pair(BOND_ASSET).totalSupply();
        address _token0 = IUniswapV2Pair(BOND_ASSET).token0();

        uint256 _bondAssetAmount;
        if (_token0 == PAYOUT_ASSET) {
            _bondAssetAmount = (_value * _totalSupply) / _reserve0;
        } else {
            _bondAssetAmount = (_value * _totalSupply) / _reserve1;
        }

        return _bondAssetAmount;
    }

    function _calculateReward(uint256 _bondAssetAmount) internal view returns (uint256, uint256) {
        (uint256 _value, uint256 _price) = _getPayoutAssetValueFromBondAsset(_bondAssetAmount);

        uint256 _reward = _value + ((_value * terms.bondDiscount) / DISCOUNT_DIVISOR);

        return (_reward, _price);
        
    }

    // TODO: VERY IMPORTANT!!!! TEST!!!!
    function _getPayoutAssetValueFromBondAsset(uint256 _bondAssetAmount) internal view returns (uint256, uint256) {
        (uint256 _reserve0, uint256 _reserve1, ) = IUniswapV2Pair(BOND_ASSET).getReserves();
        uint256 _totalSupply = IUniswapV2Pair(BOND_ASSET).totalSupply();
        address _token0 = IUniswapV2Pair(BOND_ASSET).token0();
        address _token1 = IUniswapV2Pair(BOND_ASSET).token1();
        uint8 _token0Decimals = IERC20(_token0).decimals();
        uint8 _token1Decimals = IERC20(_token1).decimals();

        uint256 _value;
        uint256 _price;
        if (_token0 == PAYOUT_ASSET) {
            _value = ((_reserve0 * _bondAssetAmount) / _totalSupply) * 2;
            _price = (_reserve1 * (10**_token0Decimals)) / _reserve0;
        } else {
            _value = ((_reserve1 * _bondAssetAmount) / _totalSupply) * 2;
            _price = (_reserve0 * (10**_token1Decimals)) / _reserve1;
        }

        return (_value, _price);
    }

    // State getters
    function getManager() public view override returns (address) {
        return IRadarBondsTreasury(TREASURY).getOwner();
    }

    function getBondingTerms() external view override returns (BondTerms memory) {
        return terms;
    }

    function getBond(address _owner) external view override returns (BondInfo memory) {
        return bonds[_owner];
    }

    function getTreasury() external view override returns (address) {
        return TREASURY;
    }

    function getStaking() external view override returns (address) {
        return STAKING;
    }

    function getPayoutAsset() external view override returns (address) {
        return PAYOUT_ASSET;
    }

    function getBondAsset() external view override returns (address) {
        return BOND_ASSET;
    }

    function estimateReward(uint256 _bondAssetAmount) external override view returns (uint256) {
        (uint256 _reward, ) =  _calculateReward(_bondAssetAmount);
        return _reward;
    }

    function getIsTrustedOrigin(address _origin) external override view returns (bool) {
        return trustedOrigins[_origin];
    }

    function getMaxBondAmount() public view override returns (uint256) {
        uint256 _bondLimit = _rewardToLPBondAsset(terms.bondPayoutLimit);
        uint256 _payoutLeftTreasury = IRadarBondsTreasury(TREASURY).getBondTokenAllowance(address(this));
        uint256 _treasuryLimit = _rewardToLPBondAsset(_payoutLeftTreasury);
        if (_bondLimit < _treasuryLimit) {
            return _bondLimit;
        } else {
            return _treasuryLimit;
        }
    }
}