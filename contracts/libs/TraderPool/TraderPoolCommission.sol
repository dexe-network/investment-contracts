// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@dlsl/dev-modules/libs/decimals/DecimalsConverter.sol";

import "../../interfaces/insurance/IInsurance.sol";
import "../../interfaces/trader/ITraderPool.sol";
import "../../interfaces/core/ICoreProperties.sol";

import "../../trader/TraderPool.sol";

import "../../libs/math/MathHelper.sol";
import "../../libs/utils/TokenBalance.sol";

library TraderPoolCommission {
    using DecimalsConverter for uint256;
    using MathHelper for uint256;
    using SafeERC20 for IERC20;
    using TokenBalance for address;

    function _calculateInvestorCommission(
        ITraderPool.PoolParameters storage poolParameters,
        uint256 investorBaseAmount,
        uint256 investorLPAmount,
        uint256 investedBaseAmount
    ) internal view returns (uint256 baseCommission, uint256 lpCommission) {
        if (investorBaseAmount > investedBaseAmount) {
            baseCommission = (investorBaseAmount - investedBaseAmount).percentage(
                poolParameters.commissionPercentage
            );
            lpCommission = investorLPAmount.ratio(baseCommission, investorBaseAmount);
        }
    }

    function nextCommissionEpoch(ITraderPool.PoolParameters storage poolParameters)
        public
        view
        returns (uint256)
    {
        return
            ITraderPool(address(this)).coreProperties().getCommissionEpochByTimestamp(
                block.timestamp,
                poolParameters.commissionPeriod
            );
    }

    function calculateCommissionOnReinvest(
        ITraderPool.PoolParameters storage poolParameters,
        address investor,
        uint256 oldTotalSupply
    )
        external
        view
        returns (
            uint256 investorBaseAmount,
            uint256 baseCommission,
            uint256 lpCommission
        )
    {
        if (oldTotalSupply > 0) {
            uint256 investorBalance = IERC20(address(this)).balanceOf(investor);
            uint256 baseTokenBalance = poolParameters.baseToken.normThisBalance();

            investorBaseAmount = baseTokenBalance.ratio(investorBalance, oldTotalSupply);

            (baseCommission, lpCommission) = calculateCommissionOnDivest(
                poolParameters,
                investor,
                investorBaseAmount,
                investorBalance
            );
        }
    }

    function calculateCommissionOnDivest(
        ITraderPool.PoolParameters storage poolParameters,
        address investor,
        uint256 investorBaseAmount,
        uint256 amountLP
    ) public view returns (uint256 baseCommission, uint256 lpCommission) {
        uint256 balance = IERC20(address(this)).balanceOf(investor);

        if (balance > 0) {
            (uint256 investedBase, ) = TraderPool(address(this)).investorsInfo(investor);
            investedBase = investedBase.ratio(amountLP, balance);

            (baseCommission, lpCommission) = _calculateInvestorCommission(
                poolParameters,
                investorBaseAmount,
                amountLP,
                investedBase
            );
        }
    }

    function calculateDexeCommission(
        uint256 baseToDistribute,
        uint256 lpToDistribute,
        uint256 dexePercentage
    ) external pure returns (uint256 lpCommission, uint256 baseCommission) {
        lpCommission = lpToDistribute.percentage(dexePercentage);
        baseCommission = baseToDistribute.percentage(dexePercentage);
    }

    function sendDexeCommission(
        IERC20 dexeToken,
        uint256 dexeCommission,
        uint256[] calldata poolPercentages,
        address[3] calldata commissionReceivers
    ) external {
        uint256[] memory receivedCommissions = new uint256[](3);
        uint256 dexeDecimals = ERC20(address(dexeToken)).decimals();

        for (uint256 i = 0; i < commissionReceivers.length; i++) {
            receivedCommissions[i] = dexeCommission.percentage(poolPercentages[i]);
            dexeToken.safeTransfer(
                commissionReceivers[i],
                receivedCommissions[i].from18(dexeDecimals)
            );
        }

        uint256 insurance = uint256(ICoreProperties.CommissionTypes.INSURANCE);

        IInsurance(commissionReceivers[insurance]).receiveDexeFromPools(
            receivedCommissions[insurance]
        );
    }
}
