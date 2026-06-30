// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSDeleverageHook} from '../../interfaces/hooks/IKSDeleverageHook.sol';
import {IKSSmartIntentHook} from '../../interfaces/hooks/IKSSmartIntentHook.sol';
import {BaseStatefulHook} from '../base/BaseStatefulHook.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';

import {
  IFlashLoanAdapter
} from 'ks-zap-aggregation-public-sc/src/interfaces/modules/flashloan/IFlashLoanAdapter.sol';
import {
  IFlashLoanReceiver
} from 'ks-zap-aggregation-public-sc/src/interfaces/modules/flashloan/IFlashLoanReceiver.sol';
import {
  ILendingActionAdapter
} from 'ks-zap-aggregation-public-sc/src/interfaces/modules/lending/ILendingActionAdapter.sol';
import {CommonLibrary} from 'ks-zap-aggregation-public-sc/src/libraries/CommonLibrary.sol';

import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';

import {IWETH} from 'ks-common-sc/src/interfaces/IWETH.sol';
import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';

contract KSDeleverageHook is BaseStatefulHook, IKSDeleverageHook, IFlashLoanReceiver {
  using TokenHelper for address;
  using CommonLibrary for *;
  using Address for *;
  using CalldataDecoder for bytes;

  IWETH internal immutable WETH;

  constructor(address[] memory initialRouters, address weth) BaseStatefulHook(initialRouters) {
    WETH = IWETH(weth);
  }

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 0, InvalidTokenData());
    require(actionData.erc721Ids.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData
  ) external onlyWhitelistedRouter returns (uint256[] memory, bytes memory beforeExecutionData) {
    DeleverageHookIntentParams calldata intentParams =
      _decodeIntentParams(intentData.coreData.hookIntentData);
    DeleverageHookActionParams calldata actionParams =
      _decodeActionParams(actionData.hookActionData);

    for (uint256 i = 0; i < actionParams.sources.length; i++) {
      bytes memory wrappedData = abi.encode(actionParams.data[i], intentData.coreData.mainAddress);

      IFlashLoanAdapter(intentParams.flashLoanAdapter)
        .flashLoan(uint256(actionParams.sources[i]), actionParams.flashLoanParams[i], wrappedData);
    }
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  )
    external
    onlyWhitelistedRouter
    returns (
      address[] memory tokens,
      uint256[] memory fees,
      uint256[] memory amounts,
      address recipient
    )
  {}

  function receiveFlashLoan(
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes calldata wrappedData
  ) external payable {
    (DeleverageSubActionParams calldata params, address mainAddress) =
      _decodeDeleverageSubActionParamsAndMainAddress(wrappedData);

    address collateralToken = tokens[0];
    uint256 flashLoanAmount = amounts[0];

    if (params.flags.at(0)) {
      collateralToken.forceApproveInf(params.swapRouter);
    }
    params.swapRouter
      .functionCallWithValue(
        params.swapData, collateralToken.isNative() ? address(this).balance : 0
      );

    if (params.flags.at(1)) {
      if (collateralToken.isNative()) {
        collateralToken = address(WETH);
      } else if (collateralToken == address(WETH)) {
        collateralToken = TokenHelper.NATIVE_ADDRESS;
      }

      if (params.debtToken.isNative()) {
        WETH.unwrapWETH();
      }
    }

    bytes memory actionCallData = abi.encodeCall(
      ILendingActionAdapter.repayAndWithdrawCollateral,
      (
        params.lendingContext,
        params.debtToken,
        params.debtToken.selfBalanceMinusOne(),
        collateralToken,
        flashLoanAmount,
        mainAddress
      )
    );
    params.lendingAdapter.functionDelegateCall(actionCallData);

    collateralToken.safeTransfer(msg.sender, flashLoanAmount);
  }

  function _decodeIntentParams(bytes calldata data)
    internal
    pure
    returns (DeleverageHookIntentParams calldata intentParams)
  {
    assembly {
      intentParams := add(data.offset, calldataload(data.offset))
    }
  }

  function _decodeActionParams(bytes calldata data)
    internal
    pure
    returns (DeleverageHookActionParams calldata actionParams)
  {
    assembly {
      actionParams := add(data.offset, calldataload(data.offset))
    }
  }

  function _decodeDeleverageSubActionParamsAndMainAddress(bytes calldata wrappedData)
    internal
    pure
    returns (DeleverageSubActionParams calldata params, address mainAddress)
  {
    bytes calldata data = wrappedData.decodeBytes(0);
    mainAddress = wrappedData.decodeAddress(1);

    assembly ('memory-safe') {
      params := add(data.offset, calldataload(data.offset))
    }
  }
}
