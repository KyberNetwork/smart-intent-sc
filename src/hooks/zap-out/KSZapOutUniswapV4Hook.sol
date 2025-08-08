// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import 'src/hooks/base/BaseHook.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/libraries/uniswapv4/StateLibrary.sol';

contract KSZapOutUniswapV4Hook is BaseHook {
  using StateLibrary for IPoolManager;
  using TokenHelper for address;

  error InvalidZapOutPosition();

  error OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96);

  error InvalidOwner();

  error GetPositionLiquidityFailed();

  error GetSqrtPriceX96Failed();

  error BelowMinRate(uint256 liquidity, uint256 minRate, uint256 outputAmount);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  struct ZapOutUniswapV4HookData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[] pools;
    address[] outputTokens;
    uint160[] sqrtPLowers;
    uint160[] sqrtPUppers;
    uint256[] minRates;
    address recipient;
  }

  modifier checkTokenLengths(TokenData calldata tokenData) override {
    require(tokenData.erc20Data.length == 0, InvalidTokenData());
    require(tokenData.erc721Data.length == 1, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(
    bytes32,
    IntentCoreData calldata coreData,
    ActionData calldata actionData
  )
    external
    view
    override
    checkTokenLengths(actionData.tokenData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.hookActionData, (uint256));

    ZapOutUniswapV4HookData memory zapOutHookData =
      abi.decode(coreData.hookIntentData, (ZapOutUniswapV4HookData));

    IPositionManager positionManager = IPositionManager(zapOutHookData.nftAddresses[index]);
    uint256 tokenId = zapOutHookData.nftIds[index];
    address outputToken = zapOutHookData.outputTokens[index];

    ERC721Data[] calldata erc721Data = actionData.tokenData.erc721Data;
    require(erc721Data[0].token == address(positionManager), InvalidTokenData());
    require(erc721Data[0].tokenId == tokenId, InvalidTokenData());

    bytes32 poolId;
    {
      (PoolKey memory poolKey,) = positionManager.getPoolAndPositionInfo(tokenId);
      poolId = _getPoolId(poolKey);
    }

    (uint160 sqrtPriceX96,,,) = positionManager.poolManager().getSlot0(poolId);
    require(
      sqrtPriceX96 >= zapOutHookData.sqrtPLowers[index]
        && sqrtPriceX96 <= zapOutHookData.sqrtPUppers[index],
      OutsidePriceRange(
        zapOutHookData.sqrtPLowers[index], zapOutHookData.sqrtPUppers[index], sqrtPriceX96
      )
    );

    uint256 liquidityBefore = positionManager.getPositionLiquidity(tokenId);
    uint256 tokenBalanceBefore = outputToken.balanceOf(zapOutHookData.recipient);

    fees = new uint256[](actionData.tokenData.erc20Data.length);
    beforeExecutionData = abi.encode(
      positionManager,
      tokenId,
      outputToken,
      liquidityBefore,
      tokenBalanceBefore,
      zapOutHookData.minRates[index],
      zapOutHookData.recipient
    );
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override returns (address[] memory, uint256[] memory, uint256[] memory, address) {
    uint256 minRate;
    uint256 liquidity;
    uint256 outputAmount;

    {
      IPositionManager positionManager;
      uint256 tokenId;
      address outputToken;
      uint256 liquidityBefore;
      uint256 tokenBalanceBefore;
      address recipient;

      (
        positionManager,
        tokenId,
        outputToken,
        liquidityBefore,
        tokenBalanceBefore,
        minRate,
        recipient
      ) = abi.decode(
        beforeExecutionData,
        (IPositionManager, uint256, address, uint256, uint256, uint256, address)
      );

      uint256 liquidityAfter = positionManager.getPositionLiquidity(tokenId);
      require(
        liquidityAfter == 0 || positionManager.ownerOf(tokenId) == coreData.mainAddress,
        InvalidOwner()
      );
      liquidity = liquidityBefore - liquidityAfter;

      outputAmount = outputToken.balanceOf(recipient) - tokenBalanceBefore;
    }

    if (outputAmount * RATE_DENOMINATOR < minRate * liquidity) {
      revert BelowMinRate(liquidity, minRate, outputAmount);
    }
  }

  function _getPoolId(PoolKey memory poolKey) internal pure returns (bytes32 poolId) {
    assembly {
      poolId := keccak256(poolKey, 0xa0)
    }
  }
}
