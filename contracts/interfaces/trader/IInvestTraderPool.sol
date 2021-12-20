// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ITraderPoolInvestProposal.sol";
import "./ITraderPool.sol";

interface IInvestTraderPool {
    function __InvestTraderPool_init(
        string calldata name,
        string calldata symbol,
        ITraderPool.PoolParameters memory _poolParameters,
        address traderPoolProposal
    ) external;

    function createProposal(
        uint256 lpAmount,
        ITraderPoolInvestProposal.ProposalLimits calldata proposalLimits,
        uint256[] calldata minPositionsOut
    ) external;

    function investProposal(
        uint256 proposalId,
        uint256 lpAmount,
        uint256[] calldata minPositionsOut
    ) external;

    function reinvestProposal(uint256 proposalId, uint256[] calldata minPositionsOut) external;

    function reinvestAllProposals(uint256[] calldata minPositionsOut) external;
}
