// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libraries/BitMask.sol';

/**
 * @notice FeeInfo is packed version of solidity structure.
 *
 * Layout: 1 bit feeMode | 24 bits protocolFee | 160 bits protocolRecipient
 */
type FeeInfo is uint256;

struct FeeInfoBuildParams {
  bool feeMode;
  uint24 protocolFee;
  address protocolRecipient;
}

using FeeInfoLibrary for FeeInfo global;
using FeeInfoLibrary for FeeInfoBuildParams global;

library FeeInfoLibrary {
  uint256 internal constant PROTOCOL_BPS_OFFSET = 160;
  uint256 internal constant FEE_MODE_OFFSET = 184;

  uint256 internal constant FEE_DENOMINATOR = 1_000_000;

  function feeMode(FeeInfo self) internal pure returns (bool _feeMode) {
    assembly ("memory-safe") {
      _feeMode := and(shr(FEE_MODE_OFFSET, self), MASK_1_BIT)
    }
  }

  function protocolFee(FeeInfo self) internal pure returns (uint24 _protocolFee) {
    assembly ("memory-safe") {
      _protocolFee := and(shr(PROTOCOL_BPS_OFFSET, self), MASK_24_BITS)
    }
  }

  function protocolRecipient(FeeInfo self) internal pure returns (address _protocolRecipient) {
    assembly ("memory-safe") {
      _protocolRecipient := and(self, MASK_160_BITS)
    }
  }

  function computeFees(FeeInfo self, uint256 totalAmount)
    internal
    pure
    returns (uint256 protocolFeeAmount, uint256 partnerFeeAmount)
  {
    unchecked {
      protocolFeeAmount = totalAmount * self.protocolFee() / FEE_DENOMINATOR;
      partnerFeeAmount = totalAmount - protocolFeeAmount;
    }
  }

  function build(FeeInfoBuildParams memory params) internal pure returns (FeeInfo feeInfo) {
    bool _feeMode = params.feeMode;
    uint24 _protocolFee = params.protocolFee;
    address _protocolRecipient = params.protocolRecipient;

    assembly ("memory-safe") {
      feeInfo := or(feeInfo, shl(FEE_MODE_OFFSET, _feeMode))
      feeInfo := or(feeInfo, shl(PROTOCOL_BPS_OFFSET, _protocolFee))
      feeInfo := or(feeInfo, _protocolRecipient)
    }
  }
}
