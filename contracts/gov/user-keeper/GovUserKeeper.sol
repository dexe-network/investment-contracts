// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@dlsl/dev-modules/libs/decimals/DecimalsConverter.sol";
import "@dlsl/dev-modules/libs/arrays/Paginator.sol";

import "../../interfaces/gov/user-keeper/IGovUserKeeper.sol";

import "../../libs/MathHelper.sol";

import "../ERC721/ERC721Power.sol";

contract GovUserKeeper is IGovUserKeeper, OwnableUpgradeable, ERC721HolderUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using MathHelper for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Paginator for EnumerableSet.UintSet;
    using DecimalsConverter for uint256;

    address public tokenAddress;
    address public nftAddress;

    NFTInfo private _nftInfo;

    uint256 private _latestPowerSnapshotId;

    mapping(address => UserInfo) private _usersInfo; // user => info
    mapping(address => BalanceInfo) private _micropoolsInfo; // user = micropool address => info

    mapping(uint256 => uint256) private _nftLockedNums; // tokenId => locked num

    mapping(uint256 => NFTSnapshot) public nftSnapshot; // snapshot id => snapshot info

    modifier withSupportedToken() {
        require(tokenAddress != address(0), "GovUK: token is not supported");
        _;
    }

    modifier withSupportedNft() {
        require(nftAddress != address(0), "GovUK: nft is not supported");
        _;
    }

    function __GovUserKeeper_init(
        address _tokenAddress,
        address _nftAddress,
        uint256 totalPowerInTokens,
        uint256 nftsTotalSupply
    ) external initializer {
        __Ownable_init();
        __ERC721Holder_init();

        require(_tokenAddress != address(0) || _nftAddress != address(0), "GovUK: zero addresses");

        tokenAddress = _tokenAddress;
        nftAddress = _nftAddress;

        if (_nftAddress != address(0)) {
            require(totalPowerInTokens > 0, "GovUK: the equivalent is zero");

            _nftInfo.totalPowerInTokens = totalPowerInTokens;

            if (IERC165(_nftAddress).supportsInterface(type(IERC721Power).interfaceId)) {
                _nftInfo.isSupportPower = true;
                _nftInfo.isSupportTotalSupply = true;
            } else if (
                IERC165(_nftAddress).supportsInterface(type(IERC721Enumerable).interfaceId)
            ) {
                _nftInfo.isSupportTotalSupply = true;
            } else {
                require(nftsTotalSupply > 0, "GovUK: total supply is zero");

                _nftInfo.totalSupply = nftsTotalSupply;
            }
        }
    }

    function depositTokens(
        address payer,
        address receiver,
        uint256 amount
    ) external override onlyOwner withSupportedToken {
        address token = tokenAddress;

        IERC20(token).safeTransferFrom(
            payer,
            address(this),
            amount.from18(ERC20(token).decimals())
        );

        _usersInfo[receiver].balanceInfo.tokenBalance += amount;
    }

    function withdrawTokens(
        address payer,
        address receiver,
        uint256 amount
    ) external override onlyOwner withSupportedToken {
        BalanceInfo storage payerBalanceInfo = _usersInfo[payer].balanceInfo;

        address token = tokenAddress;
        uint256 balance = payerBalanceInfo.tokenBalance;

        require(
            amount <= balance - payerBalanceInfo.maxTokensLocked,
            "GovUK: nothing to withdraw"
        );

        payerBalanceInfo.tokenBalance = balance - amount;

        IERC20(token).safeTransfer(receiver, amount.from18(ERC20(token).decimals()));
    }

    function delegateTokens(
        address delegator,
        address delegatee,
        uint256 amount
    ) external override onlyOwner withSupportedToken {
        UserInfo storage delegatorInfo = _usersInfo[delegator];

        uint256 balance = delegatorInfo.balanceInfo.tokenBalance;

        require(
            amount <= balance - delegatorInfo.balanceInfo.maxTokensLocked,
            "GovUK: overdelegation"
        );

        delegatorInfo.balanceInfo.tokenBalance = balance - amount;

        delegatorInfo.delegatees.add(delegatee);
        delegatorInfo.delegatedTokens[delegatee] += amount;

        _micropoolsInfo[delegatee].tokenBalance += amount;
    }

    function undelegateTokens(
        address delegator,
        address delegatee,
        uint256 amount
    ) external override onlyOwner withSupportedToken {
        UserInfo storage delegatorInfo = _usersInfo[delegator];
        BalanceInfo storage micropoolInfo = _micropoolsInfo[delegatee];

        uint256 delegated = delegatorInfo.delegatedTokens[delegatee];
        uint256 availableAmount = micropoolInfo.tokenBalance - micropoolInfo.maxTokensLocked;

        require(
            amount <= delegated && amount <= availableAmount,
            "GovUK: amount exceeds delegation"
        );

        micropoolInfo.tokenBalance -= amount;

        delegatorInfo.balanceInfo.tokenBalance += amount;
        delegatorInfo.delegatedTokens[delegatee] -= amount;

        if (
            delegatorInfo.delegatedTokens[delegatee] == 0 &&
            delegatorInfo.delegatedNfts[delegatee].length() == 0
        ) {
            delegatorInfo.delegatees.remove(delegatee);
        }
    }

    function depositNfts(
        address payer,
        address receiver,
        uint256[] calldata nftIds
    ) external override onlyOwner withSupportedNft {
        BalanceInfo storage receiverInfo = _usersInfo[receiver].balanceInfo;

        IERC721 nft = IERC721(nftAddress);

        for (uint256 i; i < nftIds.length; i++) {
            nft.safeTransferFrom(payer, address(this), nftIds[i]);

            receiverInfo.nftBalance.add(nftIds[i]);
        }
    }

    function withdrawNfts(
        address payer,
        address receiver,
        uint256[] calldata nftIds
    ) external override onlyOwner withSupportedNft {
        BalanceInfo storage payerInfo = _usersInfo[payer].balanceInfo;

        IERC721 nft = IERC721(nftAddress);

        for (uint256 i; i < nftIds.length; i++) {
            require(
                payerInfo.nftBalance.contains(nftIds[i]) && _nftLockedNums[nftIds[i]] == 0,
                "GovUK: NFT is not owned or locked"
            );

            payerInfo.nftBalance.remove(nftIds[i]);

            nft.safeTransferFrom(address(this), receiver, nftIds[i]);
        }
    }

    function delegateNfts(
        address delegator,
        address delegatee,
        uint256[] calldata nftIds
    ) external override onlyOwner withSupportedNft {
        UserInfo storage delegatorInfo = _usersInfo[delegator];
        BalanceInfo storage micropoolInfo = _micropoolsInfo[delegatee];

        for (uint256 i; i < nftIds.length; i++) {
            require(
                delegatorInfo.balanceInfo.nftBalance.contains(nftIds[i]) &&
                    _nftLockedNums[nftIds[i]] == 0,
                "GovUK: NFT is not owned or locked"
            );

            delegatorInfo.balanceInfo.nftBalance.remove(nftIds[i]);

            delegatorInfo.delegatees.add(delegatee);
            delegatorInfo.delegatedNfts[delegatee].add(nftIds[i]);

            micropoolInfo.nftBalance.add(nftIds[i]);
        }
    }

    function undelegateNfts(
        address delegator,
        address delegatee,
        uint256[] calldata nftIds
    ) external override onlyOwner withSupportedNft {
        UserInfo storage delegatorInfo = _usersInfo[delegator];
        BalanceInfo storage micropoolInfo = _micropoolsInfo[delegatee];

        for (uint256 i; i < nftIds.length; i++) {
            require(
                delegatorInfo.delegatedNfts[delegatee].contains(nftIds[i]) &&
                    micropoolInfo.nftBalance.contains(nftIds[i]) &&
                    _nftLockedNums[nftIds[i]] == 0,
                "GovUK: NFT is not owned or locked"
            );

            micropoolInfo.nftBalance.remove(nftIds[i]);

            delegatorInfo.balanceInfo.nftBalance.add(nftIds[i]);
            delegatorInfo.delegatedNfts[delegatee].remove(nftIds[i]);
        }

        if (
            delegatorInfo.delegatedTokens[delegatee] == 0 &&
            delegatorInfo.delegatedNfts[delegatee].length() == 0
        ) {
            delegatorInfo.delegatees.remove(delegatee);
        }
    }

    function tokenBalance(address voter, bool isMicropool)
        external
        view
        override
        returns (uint256)
    {
        return _getBalanceInfoStorage(voter, isMicropool).tokenBalance;
    }

    function canParticipate(
        address voter,
        bool isMicropool,
        uint256 requiredTokens,
        uint256 requiredNfts
    ) external view override returns (bool) {
        BalanceInfo storage balanceInfo = _getBalanceInfoStorage(voter, isMicropool);

        return (balanceInfo.tokenBalance >= requiredTokens ||
            balanceInfo.nftBalance.length() >= requiredNfts);
    }

    function getTotalVoteWeight() external view override returns (uint256) {
        address token = tokenAddress;

        return
            (token != address(0) ? IERC20(token).totalSupply().to18(ERC20(token).decimals()) : 0) +
            _nftInfo.totalPowerInTokens;
    }

    function getNftsPowerInTokens(uint256[] calldata nftIds, uint256 snapshotId)
        external
        view
        override
        returns (uint256)
    {
        if (nftAddress == address(0)) {
            return 0;
        }

        if (!_nftInfo.isSupportPower) {
            uint256 totalSupply;

            if (_nftInfo.isSupportTotalSupply) {
                totalSupply = nftSnapshot[snapshotId].totalSupply;
            } else {
                totalSupply = _nftInfo.totalSupply;
            }

            return
                totalSupply == 0
                    ? 0
                    : nftIds.length.ratio(_nftInfo.totalPowerInTokens, totalSupply);
        }

        uint256 nftsPower;

        for (uint256 i; i < nftIds.length; i++) {
            (, , uint256 collateralAmount, , ) = ERC721Power(nftAddress).nftInfos(nftIds[i]);

            nftsPower += collateralAmount;
        }

        uint256 totalNftsPower = nftSnapshot[snapshotId].totalNftsPower;

        if (totalNftsPower != 0) {
            uint256 totalPowerInTokens = _nftInfo.totalPowerInTokens;

            for (uint256 i; i < nftIds.length; i++) {
                nftsPower += totalPowerInTokens.ratio(
                    nftSnapshot[snapshotId].nftPower[nftIds[i]],
                    totalNftsPower
                );
            }
        }

        return nftsPower;
    }

    function createNftPowerSnapshot() external override onlyOwner returns (uint256) {
        bool isSupportPower = _nftInfo.isSupportPower;
        bool isSupportTotalSupply = _nftInfo.isSupportTotalSupply;

        if (!isSupportTotalSupply) {
            return 0;
        }

        IERC721Power nftContract = IERC721Power(nftAddress);
        uint256 supply = nftContract.totalSupply();

        uint256 currentPowerSnapshotId = ++_latestPowerSnapshotId;

        if (!isSupportPower) {
            nftSnapshot[currentPowerSnapshotId].totalSupply = supply;

            return currentPowerSnapshotId;
        }

        uint256 totalNftsPower;

        for (uint256 i; i < supply; i++) {
            uint256 index = nftContract.tokenByIndex(i);
            uint256 power = nftContract.recalculateNftPower(index);

            nftSnapshot[currentPowerSnapshotId].nftPower[index] = power;
            totalNftsPower += power;
        }

        nftSnapshot[currentPowerSnapshotId].totalNftsPower = totalNftsPower;

        return currentPowerSnapshotId;
    }

    function updateMaxTokenLockedAmount(address voter, bool isMicropool)
        external
        override
        onlyOwner
    {
        BalanceInfo storage balanceInfo = _getBalanceInfoStorage(voter, isMicropool);

        balanceInfo.maxTokensLocked = _getNewTokenLockedAmount(balanceInfo);
    }

    function lockTokens(
        uint256 proposalId,
        address voter,
        bool isMicropool,
        uint256 amount
    ) external override onlyOwner {
        BalanceInfo storage balanceInfo = _getBalanceInfoStorage(voter, isMicropool);

        balanceInfo.lockedInProposals[proposalId] += amount;
        balanceInfo.lockedProposals.add(proposalId);

        balanceInfo.maxTokensLocked = balanceInfo.maxTokensLocked.max(
            balanceInfo.lockedInProposals[proposalId]
        );
    }

    function unlockTokens(
        uint256 proposalId,
        address voter,
        bool isMicropool
    ) external override onlyOwner {
        BalanceInfo storage balanceInfo = _getBalanceInfoStorage(voter, isMicropool);

        if (balanceInfo.maxTokensLocked == 0) {
            return;
        }

        delete balanceInfo.lockedInProposals[proposalId];
        balanceInfo.lockedProposals.remove(proposalId);
    }

    function lockNfts(
        address voter,
        bool isMicropool,
        uint256[] calldata nftIds
    ) external override onlyOwner {
        BalanceInfo storage balanceInfo = _getBalanceInfoStorage(voter, isMicropool);

        for (uint256 i; i < nftIds.length; i++) {
            require(balanceInfo.nftBalance.contains(nftIds[i]), "GovUK: NFT is not owned");

            _nftLockedNums[nftIds[i]]++;
        }
    }

    function unlockNfts(uint256[] calldata nftIds) external override onlyOwner {
        for (uint256 i; i < nftIds.length; i++) {
            require(_nftLockedNums[nftIds[i]] > 0, "GovUK: NFT is not locked");

            _nftLockedNums[nftIds[i]]--;
        }
    }

    function _getNewTokenLockedAmount(BalanceInfo storage balanceInfo)
        private
        view
        returns (uint256)
    {
        uint256 lockedAmount = balanceInfo.maxTokensLocked;

        if (lockedAmount == 0) {
            return 0;
        }

        uint256 length = balanceInfo.lockedProposals.length();
        uint256 newLockedAmount;

        for (uint256 i = length; i > 0; i--) {
            newLockedAmount = newLockedAmount.max(
                balanceInfo.lockedInProposals[balanceInfo.lockedProposals.at(i - 1)]
            );

            if (newLockedAmount == lockedAmount) {
                break;
            }
        }

        return newLockedAmount;
    }

    function _getBalanceInfoStorage(address voter, bool isMicropool)
        internal
        view
        returns (BalanceInfo storage)
    {
        return isMicropool ? _micropoolsInfo[voter] : _usersInfo[voter].balanceInfo;
    }
}
