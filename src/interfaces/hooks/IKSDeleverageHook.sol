// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import {
  IFlashLoanAdapter
} from 'ks-zap-aggregation-public-sc/src/interfaces/modules/flashloan/IFlashLoanAdapter.sol';

import {PackedBits} from 'ks-zap-aggregation-public-sc/src/types/PackedBits.sol';

interface IKSDeleverageHook {
  enum LENDING_PROTOCOL {
    AAVE_V3,
    AAVE_V4
  }

  struct DeleverageHookIntentParams {
    address flashLoanAdapter;
    address swapRouter;
    address lendingAdapter;
    LENDING_PROTOCOL protocol;
    bytes validationData;
  }

  struct DeleverageHookActionParams {
    IFlashLoanAdapter.FlashLoanSource[] sources;
    bytes[] flashLoanParams;
    bytes[] data;
  }

  struct DeleverageSubActionParams {
    address lendingAdapter;
    bytes lendingContext;
    address debtToken;
    address swapRouter;
    bytes swapData;
    PackedBits flags;
  }
}
