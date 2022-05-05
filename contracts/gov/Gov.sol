// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";

import "../interfaces/gov/IGov.sol";

import "./GovFee.sol";

contract Gov is IGov, GovFee, ERC721HolderUpgradeable, ERC1155HolderUpgradeable {
    event ProposalExecuted(uint256 proposalId);

    function initialize(
        address govSettingAddress,
        address govUserKeeperAddress,
        address validatorsAddress,
        uint256 _votesLimit,
        uint256 _feePercentage
    ) external initializer {
        __GovFee_init(
            govSettingAddress,
            govUserKeeperAddress,
            validatorsAddress,
            _votesLimit,
            _feePercentage
        );
        __ERC721Holder_init();
        __ERC1155Holder_init();
    }

    function execute(uint256 proposalId) external override {
        ProposalCore storage core = proposals[proposalId].core;

        require(
            _getProposalState(core) == ProposalState.Succeeded,
            "Gov: invalid proposal status"
        );

        core.executed = true;

        address[] memory executors = proposals[proposalId].executors;
        bytes[] memory data = proposals[proposalId].data;

        for (uint256 i; i < data.length; i++) {
            (bool status, bytes memory returnedData) = executors[i].call(data[i]);

            if (!status) {
                revert(_getRevertMsg(returnedData));
            }
        }

        emit ProposalExecuted(proposalId);
    }

    receive() external payable {}

    function _getRevertMsg(bytes memory data) internal pure returns (string memory) {
        if (data.length < 68) {
            return "Transaction reverted silently";
        }

        assembly {
            data := add(data, 0x04)
        }

        return abi.decode(data, (string));
    }
}