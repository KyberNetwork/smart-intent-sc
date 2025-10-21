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
    FeeInfo feeInfo,
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

    address partnerRecipient = feeInfo.partnerRecipient();
    (uint256 protocolFeeAmount, uint256 partnerFeeAmount) = feeInfo.computeFees(fee);

    if (feeInfo.feeMode()) {
      token.safeTransferFrom(mainAddress, protocolRecipient, fee);
    } else {
      token.safeTransferFrom(mainAddress, protocolRecipient, protocolFeeAmount);
      token.safeTransferFrom(mainAddress, partnerRecipient, partnerFeeAmount);
    }

    emit IKSSmartIntentRouter.RecordVolumeAndFees(
      token, protocolRecipient, partnerRecipient, true, amount, protocolFeeAmount, partnerFeeAmount
    );
  }

  function collectFeeAfterExecution(
    address token,
    uint256 amount,
    uint256 fee,
    FeeInfo feeInfo,
    address protocolRecipient
  ) internal {
    address partnerRecipient = feeInfo.partnerRecipient();
    (uint256 protocolFeeAmount, uint256 partnerFeeAmount) = feeInfo.computeFees(fee);

    if (feeInfo.feeMode()) {
      token.safeTransfer(protocolRecipient, fee);
    } else {
      token.safeTransfer(protocolRecipient, protocolFeeAmount);
      token.safeTransfer(partnerRecipient, partnerFeeAmount);
    }

    emit IKSSmartIntentRouter.RecordVolumeAndFees(
      token, protocolRecipient, partnerRecipient, false, amount, protocolFeeAmount, partnerFeeAmount
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
