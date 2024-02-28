// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

contract BUNDLPStaking is Ownable, Pausable {
    using Address for address;

    address public stakingToken;
    address public rewardToken;
    address public WETH;
    uint256 public rewardAmount;
    uint256 public startTime;
    uint256 public stopTime;
    uint256 public duration;
    uint256 public totalStaked;
    uint256 public totalStakedRatio;
    bool public rewardLoaded;
    IUniswapV2Router02 swapRouter;

    struct Stakeholder {
        uint256 staked;
        uint256 stakedRatio; // x stakes 1 token for 10s, so staked ratio = 1 * 10
        uint256 timestamp;
    }

    mapping(address => Stakeholder) public stakeholders;
    mapping(address => bool) public withdrawn;

    event Staked(address indexed staker, uint256 amount);
    event Withdraw(address indexed staker, uint256 rewardAmount);
    event Recover(address indexed token, uint256 amount);

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardAmount,
        uint256 _startTime,
        uint256 _stopTime,
        address _router,
        address _WETH
    ) Ownable(msg.sender) {
        require(
            _rewardAmount > 0,
            "Staking: rewardAmount must be greater than zero"
        );
        require(
            _startTime > block.timestamp && _startTime < _stopTime,
            "Staking: incorrect timestamps"
        );

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardAmount = _rewardAmount;
        startTime = _startTime;
        stopTime = _stopTime;
        duration = _stopTime - _startTime;
        swapRouter = IUniswapV2Router02(_router);
        WETH = _WETH;
    }

    function loadReward() external {
        IERC20(rewardToken).transferFrom(
            msg.sender,
            address(this),
            rewardAmount
        );
        rewardLoaded = true;
    }

    function recoverTokens(IERC20 _token) external onlyOwner {
        uint256 balance = _token.balanceOf(address(this));
        _token.transfer(owner(), balance);
        emit Recover(address(_token), balance);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function stake(uint256 _amount) public virtual whenNotPaused {
        require(
            rewardLoaded,
            "Staking: Rewards not loaded into the contract yet"
        );
        require(block.timestamp >= startTime, "Staking: staking not started");
        require(block.timestamp <= stopTime, "Staking: staking period over");
        require(_amount > 0, "Staking: amount can't be 0");
        IERC20(stakingToken).transferFrom(msg.sender, address(this), _amount);
        _stake(_amount);
    }

    function exit() public virtual whenNotPaused {
        require(
            block.timestamp >= stopTime,
            "Staking: staking period not over"
        );
        Stakeholder memory stakeholder = stakeholders[msg.sender];
        require(
            stakeholder.staked > 0,
            "Staking: you have not participated in staking"
        );
        require(!withdrawn[msg.sender], "Staking: you have already withdrawn");

        withdrawn[msg.sender] = true;

        _withdrawStaked(msg.sender, stakeholder.staked);
        _withdrawReward(msg.sender, stakeholder.stakedRatio);
    }

    function earned(address _stakeholder) public view returns (uint256) {
        Stakeholder memory stakeholder = stakeholders[_stakeholder];
        if (withdrawn[_stakeholder] || stakeholder.staked == 0) return 0;
        uint256 reward = _calcReward(stakeholder.stakedRatio);
        return
            (reward * _getTimeSinceStaked(_stakeholder)) /
            (stopTime - stakeholder.timestamp);
    }

    function addAndStake(
        uint256 _tokenAmount,
        uint256 _minTokenAmount,
        uint256 _minMaticAmount,
        uint256 deadline
    ) public payable whenNotPaused {
        require(
            rewardLoaded,
            "Staking: Rewards not loaded into the contract yet"
        );
        require(block.timestamp >= startTime, "Staking: staking not started");
        require(block.timestamp <= stopTime, "Staking: staking period over");
        require(_tokenAmount > 0, "Staking: amount can't be 0");
        require(deadline > block.timestamp, "Deadline has passed");

        IERC20(rewardToken).transferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );
        IERC20(rewardToken).approve(address(swapRouter), _tokenAmount);

        uint256 liquidity = _addLiquidity(
            _tokenAmount,
            _minTokenAmount,
            msg.value,
            _minMaticAmount,
            deadline
        );
        _stake(liquidity);
    }

    function swapAndAddAndStake(uint256 _minTokenAmountOut, uint256 deadline)
        public
        payable
        whenNotPaused
    {
        require(
            rewardLoaded,
            "Staking: Rewards not loaded into the contract yet"
        );
        require(block.timestamp >= startTime, "Staking: staking not started");
        require(block.timestamp <= stopTime, "Staking: staking period over");
        require(deadline > block.timestamp, "Deadline has passed");

        (uint256 ethUsed, uint256 tokensRecieved) = _swapETH(
            _minTokenAmountOut,
            deadline
        );

        uint256 ethRemaining = msg.value - ethUsed;

        IERC20(rewardToken).approve(address(swapRouter), tokensRecieved);

        uint256 liquidity = _addLiquidity(
            tokensRecieved,
            _minTokenAmountOut,
            ethRemaining,
            0,
            deadline
        );

        _stake(liquidity);
    }

    function getRewardTokenBalance() public view returns (uint256) {
        return IERC20(rewardToken).balanceOf(address(this));
    }

    function getStakingTokenBalance() public view returns (uint256) {
        return IERC20(stakingToken).balanceOf(address(this));
    }

    function getTimeRemaining() public view returns (uint256) {
        uint256 timeRemaining = block.timestamp <= stopTime
            ? block.timestamp >= startTime
                ? stopTime - block.timestamp
                : duration
            : 0;
        return timeRemaining;
    }

    function getTimeElapsed() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp >= startTime
            ? block.timestamp <= stopTime
                ? block.timestamp - startTime
                : duration
            : 0;
        return timeElapsed;
    }

    function getStaked(address _stakeholder) public view returns (uint256) {
        return stakeholders[_stakeholder].staked;
    }

    function getTotalStakedRatio() public view returns (uint256) {
        return totalStakedRatio;
    }

    function _swapETH(uint256 _minTokenAmountOut, uint256 deadline)
        internal
        returns (uint256 ethUsed, uint256 tokensRecieved)
    {
        address[] memory _path = new address[](2);
        _path[0] = WETH;
        _path[1] = rewardToken;

        uint[] memory _amounts = swapRouter.swapExactETHForTokens{
            value: msg.value / 2
        }(_minTokenAmountOut, _path, address(this), deadline);

        ethUsed = _amounts[0];
        tokensRecieved = _amounts[1];
    }

    function _addLiquidity(
        uint256 _tokenAmount,
        uint256 _minTokenAmount,
        uint256 maticAmount,
        uint256 _minMaticAmount,
        uint256 deadline
    ) internal returns (uint256) {
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = swapRouter
            .addLiquidityETH{value: maticAmount}(
            rewardToken,
            _tokenAmount,
            _minTokenAmount,
            _minMaticAmount,
            address(this),
            deadline
        );
        if (amountToken < _tokenAmount) {
            IERC20(rewardToken).transfer(
                msg.sender,
                _tokenAmount - amountToken
            );
        }
        if (amountETH < maticAmount) {
            (bool success, ) = msg.sender.call{value: maticAmount - amountETH}(
                new bytes(0)
            );
            require(success, "ETH Transfer Failed");
        }
        return liquidity;
    }

    function _stake(uint256 _amount) internal {
        Stakeholder storage stakeholder = stakeholders[msg.sender];
        stakeholder.staked += _amount;
        uint256 stakedRatio = _amount * getTimeRemaining();
        stakeholder.stakedRatio += stakedRatio;
        if (stakeholder.timestamp == 0) {
            stakeholder.timestamp = block.timestamp;
        }

        totalStaked += _amount;
        totalStakedRatio += stakedRatio;

        emit Staked(msg.sender, _amount);
    }

    function _withdrawStaked(address _to, uint256 _amount) internal {
        IERC20(stakingToken).transfer(_to, _amount);
    }

    function _withdrawReward(address _to, uint256 _stakedRatio) internal {
        uint256 reward = _calcReward(_stakedRatio);
        IERC20(rewardToken).transfer(_to, reward);

        emit Withdraw(msg.sender, reward);
    }

    function _calcReward(uint256 _stakedRatio) internal view returns (uint256) {
        return (rewardAmount * _stakedRatio) / totalStakedRatio;
    }

    function _getTimeSinceStaked(address _stakeholder)
        internal
        view
        returns (uint256)
    {
        Stakeholder memory stakeholder = stakeholders[_stakeholder];
        return
            block.timestamp <= stopTime
                ? block.timestamp - stakeholder.timestamp
                : stopTime - stakeholder.timestamp;
    }

    receive() external payable {}

    fallback() external payable {}
}
