// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../../libs/data-structures/ShrinkableArray.sol";

/**
 * This contract is responsible for securely storing user's funds that are used during the voting. This are either
 * ERC20 tokens or NFTs
 */
interface IGovUserKeeper {
    struct BalanceInfo {
        uint256 tokenBalance;
        uint256 maxTokensLocked;
        mapping(uint256 => uint256) lockedInProposals; // proposal id => locked amount
        EnumerableSet.UintSet nftBalance; // array of NFTs
    }

    struct UserInfo {
        BalanceInfo balanceInfo;
        mapping(address => uint256) delegatedTokens; // delegatee => amount
        mapping(address => EnumerableSet.UintSet) delegatedNfts; // delegatee => tokenIds
        EnumerableSet.AddressSet delegatees;
    }

    struct NFTInfo {
        bool isSupportPower;
        bool isSupportTotalSupply;
        uint256 totalPowerInTokens;
        uint256 totalSupply;
    }

    struct NFTSnapshot {
        uint256 totalSupply;
        uint256 totalNftsPower;
        mapping(uint256 => uint256) nftPower;
    }

    function depositTokens(
        address payer,
        address receiver,
        uint256 amount
    ) external;

    function withdrawTokens(
        address payer,
        address receiver,
        uint256 amount
    ) external;

    function delegateTokens(
        address delegator,
        address delegatee,
        uint256 amount
    ) external;

    function undelegateTokens(
        address delegator,
        address delegatee,
        uint256 amount
    ) external;

    function depositNfts(
        address payer,
        address receiver,
        uint256[] calldata nftIds
    ) external;

    function withdrawNfts(
        address payer,
        address receiver,
        uint256[] calldata nftIds
    ) external;

    function delegateNfts(
        address delegator,
        address delegatee,
        uint256[] calldata nftIds
    ) external;

    function undelegateNfts(
        address delegator,
        address delegatee,
        uint256[] calldata nftIds
    ) external;

    function maxLockedAmount(address voter, bool isMicropool) external view returns (uint256);

    function tokenBalance(
        address voter,
        bool isMicropool,
        bool useDelegated
    ) external view returns (uint256 balance);

    function nftBalance(
        address voter,
        bool isMicropool,
        bool useDelegated
    ) external view returns (uint256 balance);

    function nftExactBalance(
        address voter,
        bool isMicropool,
        bool useDelegated
    ) external view returns (uint256[] memory nfts);

    function canParticipate(
        address voter,
        bool isMicropool,
        bool useDelegated,
        uint256 requiredTokens,
        uint256 requiredNfts
    ) external view returns (bool);

    function getTotalVoteWeight() external view returns (uint256);

    function getNftsPowerInTokens(uint256[] calldata nftIds, uint256 snapshotId)
        external
        view
        returns (uint256);

    function createNftPowerSnapshot() external returns (uint256);

    function getUndelegateableAssets(
        address delegator,
        address delegatee,
        ShrinkableArray.UintArray calldata lockedProposals,
        uint256[] calldata unlockedNfts
    )
        external
        view
        returns (
            uint256 undelegateableTokens,
            ShrinkableArray.UintArray memory undelegateableNfts
        );

    function getWithdrawableAssets(
        address voter,
        ShrinkableArray.UintArray calldata lockedProposals,
        uint256[] calldata unlockedNfts
    )
        external
        view
        returns (uint256 withdrawableTokens, ShrinkableArray.UintArray memory withdrawableNfts);

    function updateMaxTokenLockedAmount(
        uint256[] calldata lockedProposals,
        address voter,
        bool isMicropool
    ) external;

    function lockTokens(
        uint256 proposalId,
        address voter,
        bool isMicropool,
        uint256 amount
    ) external;

    function unlockTokens(
        uint256 proposalId,
        address voter,
        bool isMicropool
    ) external returns (uint256 unlockedAmount);

    function lockNfts(
        address voter,
        bool isMicropool,
        bool useDelegated,
        uint256[] calldata nftIds
    ) external;

    function unlockNfts(uint256[] calldata nftIds) external;
}
