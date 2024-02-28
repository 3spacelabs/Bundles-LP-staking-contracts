// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStaking {
    function stake(uint256 amount) external;

    function exit() external;

    function earned(address stakeholder) external view returns (uint256);

    function stakingToken() external view returns (address);

    function rewardToken() external view returns (address);

    function rewardAmount() external view returns (uint256);

    function startTime() external view returns (uint256);

    function stopTime() external view returns (uint256);

    function duration() external view returns (uint256);

    function totalStaked() external view returns (uint256);

    function totalStakedRatio() external view returns (uint256);

    function getRewardTokenBalance() external view returns (uint256);

    function getStakingTokenBalance() external view returns (uint256);
}