// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../interfaces/IKSSmartIntentRouter.sol';
import '../libraries/BitMask.sol';
/**
 * @notice FeeConfig is packed version of solidity structure.
 *
 * Layout: 24 bits partnerFee | 160 bits partnerRecipient
 */

type FeeConfig is uint256;

struct PartnersFeeInfo {
  bool feeMode;
  FeeConfig[] feeConfigs;
}

/**
 * @notice FeeInfo is a struct that contains the protocol recipient and the fee configs for the partners
 * @param protocolRecipient The protocol recipient
 * @param feeConfigs The fee configs for the partners
 */
struct FeeInfo {
  address protocolRecipient;
  PartnersFeeInfo[] partnersFeeInfos;
}

struct PartnersFeeInfoBuildParams {
  bool feeMode;
  uint24[] partnerFees;
  address[] partnerRecipients;
}

using FeeInfoLibrary for FeeInfo global;
using FeeInfoLibrary for FeeConfig global;
using FeeInfoLibrary for PartnersFeeInfo global;
using FeeInfoLibrary for PartnersFeeInfoBuildParams global;

library FeeInfoLibrary {
  uint256 internal constant PROTOCOL_BPS_OFFSET = 160;
  uint256 internal constant FEE_DENOMINATOR = 1_000_000;

  bytes32 constant FEE_INFO_TYPE_HASH = keccak256(
    abi.encodePacked(
      'FeeInfo(address protocolRecipient,PartnersFeeInfo[] partnersFeeInfos)PartnersFeeInfo(bool feeMode,uint256[] feeConfigs)'
    )
  );
  bytes32 constant PARTNERS_FEE_INFO_TYPE_HASH =
    keccak256(abi.encodePacked('PartnersFeeInfo(bool feeMode,uint256[] feeConfigs)'));

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

  function computeFees(PartnersFeeInfo calldata self, uint256 totalAmount)
    internal
    pure
    returns (
      uint256 protocolFeeAmount,
      uint256[] memory partnersFeeAmounts,
      address[] memory partnerRecipients
    )
  {
    unchecked {
      if (self.feeMode) {
        protocolFeeAmount = totalAmount;
      } else {
        partnersFeeAmounts = new uint256[](self.feeConfigs.length);
        partnerRecipients = new address[](self.feeConfigs.length);
        uint256 _totalPartnerFee;
        uint256 _totalPartnerFeeAmount;
        uint24 _partnerFee;

        for (uint256 i = 0; i < self.feeConfigs.length; i++) {
          _partnerFee = self.feeConfigs[i].partnerFee();
          partnerRecipients[i] = self.feeConfigs[i].partnerRecipient();

          partnersFeeAmounts[i] = totalAmount * _partnerFee / FEE_DENOMINATOR;

          _totalPartnerFee += _partnerFee;
          _totalPartnerFeeAmount += partnersFeeAmounts[i];
        }
        protocolFeeAmount = totalAmount - _totalPartnerFeeAmount;

        require(_totalPartnerFee <= FEE_DENOMINATOR, IKSSmartIntentRouter.InvalidFeeConfig());
      }
    }
  }

  function buildPartnersFeeInfo(PartnersFeeInfoBuildParams memory params)
    internal
    pure
    returns (PartnersFeeInfo memory partnersFeeInfo)
  {
    partnersFeeInfo.feeMode = params.feeMode;
    partnersFeeInfo.feeConfigs = new FeeConfig[](params.partnerFees.length);
    for (uint256 i = 0; i < params.partnerFees.length; i++) {
      partnersFeeInfo.feeConfigs[i] =
        buildFeeConfig(params.partnerFees[i], params.partnerRecipients[i]);
    }
  }

  function buildFeeConfig(uint24 _partnerFee, address _partnerRecipient)
    internal
    pure
    returns (FeeConfig feeConfig)
  {
    assembly ("memory-safe") {
      feeConfig := or(feeConfig, shl(PROTOCOL_BPS_OFFSET, _partnerFee))
      feeConfig := or(feeConfig, _partnerRecipient)
    }
  }

  function hash(FeeInfo calldata self) internal pure returns (bytes32) {
    bytes32[] memory partnersFeeInfosHashes = new bytes32[](self.partnersFeeInfos.length);
    for (uint256 i = 0; i < self.partnersFeeInfos.length; i++) {
      partnersFeeInfosHashes[i] = self.partnersFeeInfos[i].hash();
    }
    return keccak256(
      abi.encode(
        FEE_INFO_TYPE_HASH,
        self.protocolRecipient,
        keccak256(abi.encodePacked(partnersFeeInfosHashes))
      )
    );
  }

  function hash(PartnersFeeInfo calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        PARTNERS_FEE_INFO_TYPE_HASH, self.feeMode, keccak256(abi.encodePacked(self.feeConfigs))
      )
    );
  }
}
