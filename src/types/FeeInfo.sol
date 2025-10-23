// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../interfaces/IKSSmartIntentRouter.sol';
import '../libraries/BitMask.sol';
/**
 * @notice FeeConfig is packed version of solidity structure.
 *
 * Layout: 1 bit feeMode | 24 bits partnerFee | 160 bits partnerRecipient
 */

type FeeConfig is uint256;

/**
 * @notice FeeInfo is a struct that contains the protocol recipient and the fee configs for the partners
 * @param protocolRecipient The protocol recipient
 * @param partnerFeeConfigs The fee configs for the partners
 */
struct FeeInfo {
  address protocolRecipient;
  FeeConfig[][] partnerFeeConfigs;
}

struct PartnersFeeConfigBuildParams {
  bool[] feeModes;
  uint24[] partnerFees;
  address[] partnerRecipients;
}

using FeeInfoLibrary for FeeInfo global;
using FeeInfoLibrary for FeeConfig global;
using FeeInfoLibrary for PartnersFeeConfigBuildParams global;

library FeeInfoLibrary {
  uint256 internal constant PROTOCOL_BPS_OFFSET = 160;
  uint256 internal constant FEE_MODE_OFFSET = 184;
  uint256 internal constant FEE_DENOMINATOR = 1_000_000;

  bytes32 constant FEE_INFO_TYPE_HASH =
    keccak256(abi.encodePacked('FeeInfo(address protocolRecipient,uint256[][] partnerFeeConfigs)'));
  bytes32 constant PARTNERS_FEE_INFO_TYPE_HASH =
    keccak256(abi.encodePacked('PartnersFeeInfo(bool feeMode,uint256[] feeConfigs)'));

  function feeMode(FeeConfig self) internal pure returns (bool _feeMode) {
    assembly ("memory-safe") {
      _feeMode := and(shr(FEE_MODE_OFFSET, self), MASK_1_BIT)
    }
  }

  function partnerFee(FeeConfig self) internal pure returns (uint24 _partnerFee) {
    assembly ("memory-safe") {
      _partnerFee := and(shr(PROTOCOL_BPS_OFFSET, self), MASK_24_BITS)
    }
  }

  function partnerRecipient(FeeConfig self) internal pure returns (address _partnerRecipient) {
    assembly ("memory-safe") {
      _partnerRecipient := and(self, MASK_160_BITS)
    }
  }

  function computeFees(FeeConfig[] calldata self, uint256 totalAmount)
    internal
    pure
    returns (
      uint256 protocolFeeAmount,
      uint256[] memory partnersFeeAmounts,
      address[] memory partnerRecipients
    )
  {
    unchecked {
      partnersFeeAmounts = new uint256[](self.length);
      partnerRecipients = new address[](self.length);
      uint256 _totalPartnerFee;
      uint256 _totalPartnerFeeAmount;
      uint256 _feeAmount;
      uint24 _partnerFee;

      for (uint256 i = 0; i < self.length; i++) {
        _partnerFee = self[i].partnerFee();
        _feeAmount = (totalAmount * _partnerFee) / FEE_DENOMINATOR;
        partnerRecipients[i] = self[i].partnerRecipient();

        if (!self[i].feeMode()) {
          partnersFeeAmounts[i] = _feeAmount;
          _totalPartnerFee += _partnerFee;
          _totalPartnerFeeAmount += _feeAmount;
        }
      }
      protocolFeeAmount += totalAmount - _totalPartnerFeeAmount;

      require(_totalPartnerFee <= FEE_DENOMINATOR, IKSSmartIntentRouter.InvalidFeeConfig());
    }
  }

  function buildPartnersConfigs(PartnersFeeConfigBuildParams memory params)
    internal
    pure
    returns (FeeConfig[] memory feeConfigs)
  {
    feeConfigs = new FeeConfig[](params.partnerFees.length);
    for (uint256 i = 0; i < params.partnerFees.length; i++) {
      feeConfigs[i] =
        buildFeeConfig(params.partnerFees[i], params.partnerRecipients[i], params.feeModes[i]);
    }
  }

  function buildFeeConfig(uint24 _partnerFee, address _partnerRecipient, bool _feeMode)
    internal
    pure
    returns (FeeConfig feeConfig)
  {
    assembly ("memory-safe") {
      feeConfig := or(feeConfig, shl(FEE_MODE_OFFSET, _feeMode))
      feeConfig := or(feeConfig, shl(PROTOCOL_BPS_OFFSET, _partnerFee))
      feeConfig := or(feeConfig, _partnerRecipient)
    }
  }

  function hash(FeeInfo calldata self) internal pure returns (bytes32) {
    bytes32[] memory partnersFeeConfigsHashes = new bytes32[](self.partnerFeeConfigs.length);
    for (uint256 i = 0; i < self.partnerFeeConfigs.length; i++) {
      partnersFeeConfigsHashes[i] = keccak256(abi.encodePacked(self.partnerFeeConfigs[i]));
    }
    return keccak256(
      abi.encode(
        FEE_INFO_TYPE_HASH,
        self.protocolRecipient,
        keccak256(abi.encodePacked(partnersFeeConfigsHashes))
      )
    );
  }
}
