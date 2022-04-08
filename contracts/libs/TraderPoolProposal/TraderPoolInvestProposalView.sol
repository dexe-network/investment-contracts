// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../interfaces/trader/ITraderPoolInvestProposal.sol";
import "../../interfaces/core/IPriceFeed.sol";

import "../../libs/MathHelper.sol";
import "../../libs/DecimalsConverter.sol";

import "../../trader/TraderPoolInvestProposal.sol";

library TraderPoolInvestProposalView {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using DecimalsConverter for uint256;
    using MathHelper for uint256;
    using Math for uint256;
    using Address for address;

    function getProposalInfos(
        mapping(uint256 => ITraderPoolInvestProposal.ProposalInfo) storage proposalInfos,
        uint256 offset,
        uint256 limit
    ) external view returns (ITraderPoolInvestProposal.ProposalInfo[] memory proposals) {
        uint256 to = (offset + limit)
            .min(TraderPoolInvestProposal(address(this)).proposalsTotalNum())
            .max(offset);

        proposals = new ITraderPoolInvestProposal.ProposalInfo[](to - offset);

        for (uint256 i = offset; i < to; i++) {
            proposals[i - offset] = proposalInfos[i + 1];
        }
    }

    function getActiveInvestmentsInfo(
        EnumerableSet.UintSet storage activeInvestments,
        mapping(address => mapping(uint256 => uint256)) storage lpBalances,
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (ITraderPoolInvestProposal.ActiveInvestmentInfo[] memory investments) {
        uint256 to = (offset + limit).min(activeInvestments.length()).max(offset);
        investments = new ITraderPoolInvestProposal.ActiveInvestmentInfo[](to - offset);

        for (uint256 i = offset; i < to; i++) {
            uint256 proposalId = activeInvestments.at(i);

            investments[i - offset] = ITraderPoolInvestProposal.ActiveInvestmentInfo(
                proposalId,
                TraderPoolInvestProposal(address(this)).balanceOf(user, proposalId),
                lpBalances[user][proposalId]
            );
        }
    }

    function getRewards(
        mapping(uint256 => ITraderPoolInvestProposal.RewardInfo) storage rewardInfos,
        mapping(address => mapping(uint256 => ITraderPoolInvestProposal.UserRewardInfo))
            storage userRewardInfos,
        uint256[] calldata proposalIds,
        address user
    ) external view returns (ITraderPoolInvestProposal.Receptions memory receptions) {
        uint256 proposalsTotalNum = TraderPoolInvestProposal(address(this)).proposalsTotalNum();
        receptions.rewards = new TraderPoolInvestProposal.Reception[](proposalIds.length);

        address baseToken = ITraderPoolInvestProposal(address(this)).getBaseToken();

        for (uint256 i = 0; i < proposalIds.length; i++) {
            uint256 proposalId = proposalIds[i];

            if (proposalId > proposalsTotalNum) {
                continue;
            }

            TraderPoolInvestProposal.UserRewardInfo storage userRewardInfo = userRewardInfos[user][
                proposalId
            ];
            TraderPoolInvestProposal.RewardInfo storage rewardInfo = rewardInfos[proposalId];

            uint256 balance = TraderPoolInvestProposal(address(this)).balanceOf(user, proposalId);

            receptions.rewards[i].tokens = rewardInfo.rewardTokens.values();
            receptions.rewards[i].amounts = new uint256[](receptions.rewards[i].tokens.length);

            for (uint256 j = 0; j < receptions.rewards[i].tokens.length; j++) {
                address token = receptions.rewards[i].tokens[j];

                receptions.rewards[i].amounts[j] =
                    userRewardInfo.rewardsStored[token] +
                    ((rewardInfo.cumulativeSums[token] -
                        userRewardInfo.cumulativeSumsStored[token]) * balance) /
                    PRECISION;

                if (token == baseToken) {
                    receptions.baseAmount += receptions.rewards[i].amounts[j];
                }
            }
        }
    }
}
