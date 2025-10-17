// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// import {RevertReasonParser} from 'contracts/common/RevertReasonParser.sol';
import 'forge-std/Test.sol';
import 'forge-std/console.sol';
import 'src/KSSmartIntentRouter.sol';

contract SimulateIntent is Test {
  // Test parameters
  string public RPC_URL;
  uint256 public BLOCK_NUMBER;
  address public SENDER;
  address public TARGET;
  bytes public CALL_DATA;
  uint256 public ETH_VALUE;

  function setUp() public {
    // (Step 1) Load parameters
    RPC_URL = vm.envString('BASE_NODE_URL');
    BLOCK_NUMBER = 0;
    SENDER = 0x5ACf6f6E6c0a5B8595251416B50F6c7CF9508F7E;
    TARGET = 0xCa611DEb2914056D392bF77e13aCD544334dD957;
    ETH_VALUE = 0;
    CALL_DATA = hex'';

    if (BLOCK_NUMBER != 0) {
      vm.createSelectFork(RPC_URL, BLOCK_NUMBER);
    } else {
      vm.createSelectFork(RPC_URL);
    }

    // (Step 2) Set up transaction context
    deal(SENDER, ETH_VALUE);
  }

  function testSimulateZapTransaction() public {
    uint256 currentBlock = block.number;

    console.log('=== Simulation Setup ===');
    console.log('Block number:', currentBlock);
    console.log('Sender:', SENDER);
    console.log('Target:', TARGET);
    console.log('Calldata length:', CALL_DATA.length);
    console.log('ETH value:', ETH_VALUE);

    vm.startPrank(SENDER);

    // Execute the transaction with value and calldata
    (bool success, bytes memory returnData) = TARGET.call{value: ETH_VALUE}(CALL_DATA);

    // Log transaction result
    if (success) {
      console.log('Transaction status: SUCCESS');
      if (returnData.length > 0) {
        console.log('Return data:');
        console.logBytes(returnData);
      } else {
        console.log('No return data');
      }
    } else {
      console.log('Transaction status: FAILED');
    }
  }

  function excludeSig(bytes calldata data) public pure returns (bytes memory) {
    return data[4:];
  }
}
