// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/interfaces/IKSGenericForwarder.sol';

import 'ks-common-sc/src/libraries/token/PermitHelper.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

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

  /// @notice Thrown when collecting more than the intent allowance for ERC20
  error ERC20InsufficientIntentAllowance(
    bytes32 intentHash, address token, uint256 allowance, uint256 needed
  );

  bytes32 constant ERC20_DATA_TYPE_HASH =
    keccak256(abi.encodePacked('ERC20Data(address token,uint256 amount,bytes permitData)'));

  function hash(ERC20Data calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(ERC20_DATA_TYPE_HASH, self.token, self.amount, keccak256(self.permitData))
    );
  }

  function approve(
    ERC20Data calldata self,
    mapping(bytes32 => mapping(address => uint256)) storage allowances,
    bytes32 intentHash,
    address mainAddress
  ) internal {
    allowances[intentHash][self.token] = self.amount;
    if (self.permitData.length > 0) {
      self.token.erc20Permit(mainAddress, self.permitData);
    }
  }

  function collect(
    ERC20Data calldata self,
    mapping(bytes32 => mapping(address => uint256)) storage allowances,
    bytes32 intentHash,
    address mainAddress,
    address actionContract,
    IKSGenericForwarder forwarder,
    address feeRecipient,
    uint256 fee,
    bool approvalFlag
  ) internal {
    address token = self.token;
    uint256 amount = self.amount;

    uint256 allowance = allowances[intentHash][token];
    if (allowance < amount) {
      revert ERC20InsufficientIntentAllowance(intentHash, token, allowance, amount);
    }

    unchecked {
      allowances[intentHash][token] = allowance - amount;
    }

    if (address(forwarder) == address(0)) {
      token.safeTransferFrom(mainAddress, address(this), amount - fee);
      token.safeTransferFrom(mainAddress, feeRecipient, fee);
      if (approvalFlag) {
        token.forceApprove(actionContract, type(uint256).max);
      }
    } else {
      token.safeTransferFrom(mainAddress, address(forwarder), amount - fee);
      token.safeTransferFrom(mainAddress, feeRecipient, fee);
      if (approvalFlag) {
        forwardApproveInf(forwarder, token, actionContract);
      }
    }
  }

  function forwardApproveInf(IKSGenericForwarder forwarder, address token, address spender)
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
