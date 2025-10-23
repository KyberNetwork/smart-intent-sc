// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/interfaces/IKSGenericForwarder.sol';
import 'ks-common-sc/src/libraries/token/PermitHelper.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import '../interfaces/IKSSmartIntentRouter.sol';
import './FeeInfo.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

/**
 * @notice Data structure for ERC20 token
 * @param token The address of the ERC20 token
 * @param amount The amount of the ERC20 token
 * @param permitData The permit data for the ERC20 token
 */
struct ERC20Data {
  address token;
  uint256 amount;
  bytes permitData;
}

using ERC20DataLibrary for ERC20Data global;

library ERC20DataLibrary {
  using PermitHelper for address;
  using TokenHelper for address;

  bytes32 constant ERC20_DATA_TYPE_HASH =
    keccak256(abi.encodePacked('ERC20Data(address token,uint256 amount,bytes permitData)'));

  function hash(ERC20Data calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(ERC20_DATA_TYPE_HASH, self.token, self.amount, keccak256(self.permitData))
    );
  }

  function collect(
    address token,
    uint256 amount,
    address mainAddress,
    address actionContract,
    uint256 fee,
    bool approvalFlag,
    IKSGenericForwarder forwarder,
    FeeConfig[] calldata partnerFeeConfigs,
    address protocolRecipient
  ) internal {
    if (address(forwarder) == address(0)) {
      token.safeTransferFrom(mainAddress, address(this), amount - fee);
      if (approvalFlag) {
        token.forceApprove(actionContract, type(uint256).max);
      }
    } else {
      token.safeTransferFrom(mainAddress, address(forwarder), amount - fee);
      if (approvalFlag) {
        _forwardApproveInf(forwarder, token, actionContract);
      }
    }

    (
      uint256 protocolFeeAmount,
      uint256[] memory partnersFeeAmounts,
      address[] memory partnerRecipients
    ) = FeeInfoLibrary.computeFees(partnerFeeConfigs, fee);

    token.safeTransferFrom(mainAddress, protocolRecipient, protocolFeeAmount);
    for (uint256 i = 0; i < partnersFeeAmounts.length; i++) {
      token.safeTransferFrom(mainAddress, partnerRecipients[i], partnersFeeAmounts[i]);
    }

    emit IKSSmartIntentRouter.RecordVolumeAndFees(
      token,
      protocolRecipient,
      partnerRecipients,
      protocolFeeAmount,
      partnersFeeAmounts,
      true,
      amount
    );
  }

  function collectFeeAfterExecution(
    address token,
    uint256 amount,
    uint256 fee,
    FeeConfig[] calldata partnerFeeConfigs,
    address protocolRecipient
  ) internal {
    (
      uint256 protocolFeeAmount,
      uint256[] memory partnersFeeAmounts,
      address[] memory partnerRecipients
    ) = FeeInfoLibrary.computeFees(partnerFeeConfigs, fee);

    token.safeTransfer(protocolRecipient, protocolFeeAmount);
    for (uint256 i = 0; i < partnersFeeAmounts.length; i++) {
      token.safeTransfer(partnerRecipients[i], partnersFeeAmounts[i]);
    }

    emit IKSSmartIntentRouter.RecordVolumeAndFees(
      token,
      protocolRecipient,
      partnerRecipients,
      protocolFeeAmount,
      partnersFeeAmounts,
      false,
      amount
    );
  }

  function _forwardApproveInf(IKSGenericForwarder forwarder, address token, address spender)
    internal
  {
    bytes memory approveCalldata = abi.encodeCall(IERC20.approve, (spender, type(uint256).max));
    try forwarder.forward(token, approveCalldata) {}
    catch {
      approveCalldata = abi.encodeCall(IERC20.approve, (spender, 0));
      forwarder.forward(token, approveCalldata);
      approveCalldata = abi.encodeCall(IERC20.approve, (spender, type(uint256).max));
      forwarder.forward(token, approveCalldata);
    }
  }
}
