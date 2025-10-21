// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libraries/BitMask.sol';

/**
 * @notice FeeInfo is packed version of solidity structure.
 *
 * Layout: 1 bit feeMode | 24 bits partnerFee | 160 bits partnerRecipient
 */
type FeeInfo is uint256;

struct FeeInfoBuildParams {
  bool feeMode;
  uint24 partnerFee;
  address partnerRecipient;
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

  function partnerFee(FeeInfo self) internal pure returns (uint24 _partnerFee) {
    assembly ("memory-safe") {
      _partnerFee := and(shr(PROTOCOL_BPS_OFFSET, self), MASK_24_BITS)
    }
  }

  function partnerRecipient(FeeInfo self) internal pure returns (address _partnerRecipient) {
    assembly ("memory-safe") {
      _partnerRecipient := and(self, MASK_160_BITS)
    }
  }

  function computeFees(FeeInfo self, uint256 totalAmount)
    internal
    pure
    returns (uint256 protocolFeeAmount, uint256 partnerFeeAmount)
  {
    unchecked {
      partnerFeeAmount = totalAmount * self.partnerFee() / FEE_DENOMINATOR;
      protocolFeeAmount = totalAmount - partnerFeeAmount;
    }
  }

  function build(FeeInfoBuildParams memory params) internal pure returns (FeeInfo feeInfo) {
    bool _feeMode = params.feeMode;
    uint24 _partnerFee = params.partnerFee;
    address _partnerRecipient = params.partnerRecipient;

    assembly ("memory-safe") {
      feeInfo := or(feeInfo, shl(FEE_MODE_OFFSET, _feeMode))
      feeInfo := or(feeInfo, shl(PROTOCOL_BPS_OFFSET, _partnerFee))
      feeInfo := or(feeInfo, _partnerRecipient)
    }
  }
}
