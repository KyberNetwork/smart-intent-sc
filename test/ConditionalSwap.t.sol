// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import 'src/hooks/swap/KSConditionalSwapHook.sol';

import {OracleLib} from 'src/libraries/OracleLib.sol';

import {MockChainlinkFeed} from './mocks/MockChainlinkFeed.sol';
import {MockPyth} from './mocks/MockPyth.sol';

contract ConditionalSwapTest is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using ArraysHelper for *;

  bytes swapdata =
    hex'00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000007a000000000000000000000000000000000000000000000000000000000000009e000000000000000000000000000000000000000000000000000000000000006e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000002e234DAe75C793f67A35089C9d99245E1C58470b0000000000000000000000000000000000000000000000000000000067db987b00000000000000000000000000000000000000000000000000000000000006800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000040f59b1df7000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000002000000000000000000000000066a9893cc07d91d95644aedd05d03f95e1dba8af000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000002300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040a9d4c672000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000180000000000000000000000000655edce464cc797526600a462a8154650eee4b77000000000000000000000000000000000000000000000000000000003b9d5f1a000000000000000000000000000000000000000000000000000000003b9d5f1a00000000000000000000000000000000000000000000000006dac07944b594800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000005fa94793ea0000001a371930340fc8fbcc09c409c467db9414000000000000000000000000000000000000000000000000000000000000001bdcffd1bf68c2c17dcf00a25c935efba96aa63b7f75dd43d42b3df2cf7273c2260fb4b38a9db829fbfdabcc6262ac3982f1d31366bfde12a7b67f6f31ba52b2cb0000000000000000000000000000000000000000000000000000000000000040d90ce4910000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001000000000000000000000000007f86bf177dd4f3494b841a37e810a34dd56c829b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000006da929a6bb58cc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000010000000000000000000000000011cbb0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000002e234DAe75C793f67A35089C9d99245E1C58470b000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000011c7210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024f7b22536f75726365223a22222c22416d6f756e74496e555344223a22313030302e31373135393231313738353037222c22416d6f756e744f7574555344223a22313030302e34373538333032323939323331222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a2231313636323536222c2254696d657374616d70223a313734323434333436392c22526f7574654944223a2263383438663432632d326465322d343364382d623366372d636637366362666430363536222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224e39426b4975436430714961362f4d64736635717a61657863436c3754413539426e4d70454741437a74432b5875325176494a36444c34476b7075746b636f627554395657357a42744e427a5463736b4e7768434662372f6f52675173676970424e693878716d323869524b3048496834527a70316457512f437737676a58375168653270313853506966492b7550674e5a34647a5a6a4461686b664d416852796d7765783233714942536a65565a6f44483932596a534b4e546176396f2f2f634754766476336a52555538536841763153464b55514b54515470682f4d4f71534f7370646c37306632714155705274566d7739434b4d383347726164506b55546f5854684a2f6c734e784561634267395a37617a363837394d366d31517538465a687237796374367a4242524a774171464e6646436a364b523969307a4e702f665a2b6876394b6970455341666d5078634e4d67773d3d227d7d0000000000000000000000000000000000';
  bytes swapdata2 =
    hex'00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000007a000000000000000000000000000000000000000000000000000000000000009e000000000000000000000000000000000000000000000000000000000000006e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000003674eD9c52D903C6c3A468592Ac27Fe71B3CD8490000000000000000000000000000000000000000000000000000000067db987b00000000000000000000000000000000000000000000000000000000000006800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000040f59b1df7000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000002000000000000000000000000066a9893cc07d91d95644aedd05d03f95e1dba8af000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000002300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040a9d4c672000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000180000000000000000000000000655edce464cc797526600a462a8154650eee4b77000000000000000000000000000000000000000000000000000000003b9d5f1a000000000000000000000000000000000000000000000000000000003b9d5f1a00000000000000000000000000000000000000000000000006dac07944b594800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000005fa94793ea0000001a371930340fc8fbcc09c409c467db9414000000000000000000000000000000000000000000000000000000000000001bdcffd1bf68c2c17dcf00a25c935efba96aa63b7f75dd43d42b3df2cf7273c2260fb4b38a9db829fbfdabcc6262ac3982f1d31366bfde12a7b67f6f31ba52b2cb0000000000000000000000000000000000000000000000000000000000000040d90ce4910000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001000000000000000000000000007f86bf177dd4f3494b841a37e810a34dd56c829b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000006da929a6bb58cc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000010000000000000000000000000011cbb0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000003674eD9c52D903C6c3A468592Ac27Fe71B3CD849000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000011c7210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024f7b22536f75726365223a22222c22416d6f756e74496e555344223a22313030302e31373135393231313738353037222c22416d6f756e744f7574555344223a22313030302e34373538333032323939323331222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a2231313636323536222c2254696d657374616d70223a313734323434333436392c22526f7574654944223a2263383438663432632d326465322d343364382d623366372d636637366362666430363536222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224e39426b4975436430714961362f4d64736635717a61657863436c3754413539426e4d70454741437a74432b5875325176494a36444c34476b7075746b636f627554395657357a42744e427a5463736b4e7768434662372f6f52675173676970424e693878716d323869524b3048496834527a70316457512f437737676a58375168653270313853506966492b7550674e5a34647a5a6a4461686b664d416852796d7765783233714942536a65565a6f44483932596a534b4e546176396f2f2f634754766476336a52555538536841763153464b55514b54515470682f4d4f71534f7370646c37306632714155705274566d7739434b4d383347726164506b55546f5854684a2f6c734e784561634267395a37617a363837394d366d31517538465a687237796374367a4242524a774171464e6646436a364b523969307a4e702f665a2b6876394b6970455341666d5078634e4d67773d3d227d7d0000000000000000000000000000000000';

  bytes pythUpdateData =
    hex'504e41550100000003b801000000040d00276f5b9bbd57764e3c885b2a93e2ec99e4410dddea133e2bcf6e6d2aa52220782156d586e84d0e4cd3174b4bd6f1451953c7d876cf5064c87f55ce2a661e8fee0102d23f5a5f808768e508584832f35dc3596d32630b52a05ff2f71e33d4d5333aa5672b33b488bb34d369258b1a49145244773a70e60d30306251b1634d2324bb2d01031056f9f2942476f131cbedc5b44d5582fd32b83c0ba9383b478e80c959e31af01fa88f50a33aeb7ab729d69a07d83fcba54f8f554e9c4060859ab762d3bff8f30004358c5fafc18f869fe8c1db5e2ebe2bdc8e501b8ad6c295740dd95eb878afd31358608385a66fdeeadc4c432560b51dfd2e1f57724e74bb3dd84197f0851068dc0106d9cc8e4f18b56badaf8e2f09ba38bfeadf5629780ff6ea3a396b4a3d631a1fce045552446529688efdc9c70d433faf55fbd10cf4a10d6aaa41d789eec29d30d90008877c385d9bfc1c69dcb82274cd076fc58086fb1e5b22eb50e5e11881e575125646de23f3656202b81402b3ab748b868fdce8abb5770a4e59c0a47e8794b2406c010a0f95e7560379535f9915806a8030dd90d732efdc9149a693ca611081b4ad01956cae625662a018eaa379bebcc75a58abff2334d8d21f736cba254c589ced4f5d010b48b5be572a2cadfc1fd0f74c23d7a8b43629e7c3600d1caa122d3932a370a9917a7ae16986001b931ad19a7167fc060ba3c328197d764f5a0f40f2c4c659c84e010cbd3cb104da104d83fb030623b292c046e8c7ab876866e9bf9444c31aa275f09b362e0cd2caf5d63fc67a4b4582351c00048258fc222fdcafd3a4f5cd973becdd000d6eb0c29f38df7fec3c52307caccf275999aded023f9d79048b17f98e184b6ac02dcdbd93dd6d146b59324d12f486336b110a2f814ff66c1ff299ff1427892b45000e5234724fad66ff9688510b538ad695dc8bcdce669b38f72fd6e0a276f173cc68571930fb308a047df9bb7f06a557b563d58484ca9d9e2bcecc387df20e3dd4d3010fd87f033e76d841cdf14bd2624008ef4f511bde4428590ba9f9fa782073afd96d744881c9bf908d6475b47d24dede2c5ab06c91c7b4df3b7a4b5c9818ec43e4f90010133189f049dcd388beb6a4063c9eeea9a2a54476efb79c3d39628e356673b278602849af9b6a0b9adbab8e72f533a5e9646441f813d8c8c37e985b5c064ad81a0067db904300000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa7100000000072d7058014155575600000000000c3a7d8c00002710a12a5869dbbb38a8795bc72942ca40da9e0a5bd8020055002b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b0000000005f6114f000000000000cda2fffffff80000000067db90430000000067db90420000000005f62653000000000000c5fa0cf52e2fe61280a39fe1b0710570a8df3293aaa7de950fbd77cb5a9fbd59efa8dae4ab333f4623a6936389052ab8b87098037e3541b7f5129257ad431e1806877866609c1fe71baae65c5c37c57825175aebe80f309cd48099b0040d6fb38f2dabac57e0717fb9b2ab916b0a94b4e931461438894d93a442dc6ccf8fb68da2a537171a52cfde7dea9243ee43193dcd7446429a85eb799e62d4fd72c56961aa0e0e33ce0488bd5938e05e1b4827d468d1732ba3e438bd99e2f0078e28842b59ee0f82f3cdf61b5ba8551bed77011a454079dba4ec47ddd6fd94450dc2c0928a53ac035b7de3792b6fe71bbd489f67c1e6aa005500e62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43000007d16accffee00000000b1996851fffffff80000000067db90430000000067db9042000007d28b80ca4000000000bb14fbe80c73f40b6db4e39c00925c7d4c84e1da7a8f37bd95eb84812d210638850ea96d6b329964e81f75212ebdf8e7c5675b3449ba832014978ffa3f1aed4deb93c5355b06ab4a3cacc8e34f7f6e8e80e7a10de0f35cf6decc07c0b0409c8df3c3c90825d03d32e967b339885cf7dccc198e304ad02c5aa511e41519b898676021f3d4b43202ac5c01dc85a1fa3eecc7b649a1ca1a59b6e052cfd234141ab494bf1316b43c9bde3d074cea1b35d3726f16e6e3d8189b8aedc64c1fce8b2ad65ec2d36e0332101da6b69b19325a8d91369a0974404bce4596d217d9008dbe3217928a53ac035b7de3792b6fe71bbd489f67c1e6aa';

  uint256 feeBefore;
  uint256 feeAfter;
  uint256 maxSrcFee;
  uint256 maxDstFee;

  uint256 swapAmount = 1_000_000_000;

  KSConditionalSwapHook conditionalSwapHook;
  uint256 currentPrice = 11_662_550_000_000; // USDC/BTC denominated by 1e18

  // tokenIn = USDT (6 decimals), tokenOut = WBTC (8 decimals) on the mainnet fork.
  // Per-token USD prices, USD-per-whole-token scaled by 1e18:
  uint256 internal constant USDT_USD = 1e18; // $1
  uint256 internal constant BTC_USD = 100_000e18; // $100k
  // Derived swap ratio (amountOut_raw * 1e18 / amountIn_raw) for the mock prices: 1e15.
  uint256 internal constant ORACLE_RATIO = 1e15;
  uint256 internal constant PYTH_FEE = 0.001 ether;

  bytes32 internal constant USDT_ID = keccak256('USDT/USD');
  bytes32 internal constant WBTC_ID = keccak256('WBTC/USD');

  // --- Real mainnet oracle infrastructure (fork tests) ---
  address internal constant CHAINLINK_USDT_USD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  // WBTC tracks BTC; use the canonical BTC/USD aggregator for the WBTC leg.
  address internal constant CHAINLINK_WBTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
  address internal constant PYTH_MAINNET = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
  bytes32 internal constant PYTH_USDT_USD =
    0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b;
  bytes32 internal constant PYTH_BTC_USD =
    0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

  MockChainlinkFeed internal feedIn;
  MockChainlinkFeed internal feedOut;
  MockPyth internal pyth;

  function setUp() public virtual override {
    super.setUp();

    address[] memory routers = new address[](1);
    routers[0] = address(router);
    deal(tokenOut, address(mockActionContract), 1e30);
    deal(tokenIn, mainAddress, 1e30);

    conditionalSwapHook = new KSConditionalSwapHook(routers);
    // fund the hook so it can pay Pyth update fees out of its own balance
    vm.deal(address(conditionalSwapHook), 1 ether);

    // mock oracles
    feedIn = new MockChainlinkFeed(8, 1e8); // USDT/USD = $1
    feedOut = new MockChainlinkFeed(8, int256(100_000e8)); // WBTC/USD = $100k
    pyth = new MockPyth(PYTH_FEE);
  }

  function _emptyLeg() internal pure returns (OracleLib.TokenOracle memory) {
    return OracleLib.TokenOracle(OracleLib.OracleType.NONE, address(0), bytes32(0), 0);
  }

  function _chainlinkLeg(address feed, uint256 priceLimits)
    internal
    pure
    returns (OracleLib.TokenOracle memory)
  {
    return OracleLib.TokenOracle(OracleLib.OracleType.CHAINLINK, feed, bytes32(0), priceLimits);
  }

  function _pythLeg(address pyth_, bytes32 priceId, uint256 priceLimits)
    internal
    pure
    returns (OracleLib.TokenOracle memory)
  {
    return OracleLib.TokenOracle(OracleLib.OracleType.PYTH, pyth_, priceId, priceLimits);
  }

  function _config(
    OracleLib.TokenOracle memory oracleIn,
    OracleLib.TokenOracle memory oracleOut,
    uint256 oracleParams
  ) internal pure returns (OracleLib.OracleConfig memory) {
    return OracleLib.OracleConfig(oracleIn, oracleOut, oracleParams);
  }

  function _noOracle() internal pure returns (OracleLib.OracleConfig memory) {
    return _config(_emptyLeg(), _emptyLeg(), 0);
  }

  /// @dev oracleParams packed: maxStaleness 128bits | maxDeviationBps 128bits.
  function _params(uint256 maxStaleness, uint256 maxDeviationBps) internal pure returns (uint256) {
    return (maxStaleness << 128) | maxDeviationBps;
  }

  /// @dev USD price band [price*(1-bpsBelow), price*(1+bpsAbove)], packed min 128 | max 128.
  function _band(uint256 price, uint256 bpsBelow, uint256 bpsAbove)
    internal
    pure
    returns (uint256)
  {
    uint256 lower = (price * (10_000 - bpsBelow)) / 10_000;
    uint256 upper = (price * (10_000 + bpsAbove)) / 10_000;
    return (lower << 128) | upper;
  }

  uint256 internal constant FULL_BAND = (uint256(0) << 128) | type(uint128).max;

  // ---------------------------------------------------------------------------
  // Non-oracle conditional swap tests
  // ---------------------------------------------------------------------------

  struct TestFuzz_ConditionalSwap_Params {
    uint256 mode;
    uint256 maxFeeBefore;
    uint256 maxFeeAfter;
    uint256 srcFee;
    uint256 dstFee;
    uint256 amountIn;
    uint256 returnAmount;
  }

  function testFuzz_ConditionalSwap(TestFuzz_ConditionalSwap_Params memory params) public {
    params.mode = bound(params.mode, 0, 2);
    params.maxFeeBefore = bound(params.maxFeeBefore, 0, 1_000_000);
    params.maxFeeAfter = bound(params.maxFeeAfter, 0, 1_000_000);
    params.srcFee = bound(params.srcFee, 0, 1_000_000);
    params.dstFee = bound(params.dstFee, 0, 1_000_000);
    params.amountIn = bound(params.amountIn, 100, 1_000_000e6);
    params.returnAmount = bound(params.returnAmount, 100, 1_000_000e8);

    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    intentData.tokenData.erc20Data[0].amount = amountIn;
    _setUpMainAddress(intentData, false);

    uint256 beforeSwapFee = (amountIn * feeBefore) / 1_000_000;
    uint256 afterSwapFee = (params.returnAmount * feeAfter) / 1_000_000;

    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(
        tokenIn,
        tokenOut,
        amountIn - beforeSwapFee,
        params.returnAmount,
        feeAfter == 0 ? mainAddress : address(router),
        mainAddress
      ),
      true
    );

    params.returnAmount = params.returnAmount - afterSwapFee;

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(params.mode, intentData, actionData);

    uint256[2] memory routerBefore =
      [tokenIn.balanceOf(address(router)), tokenOut.balanceOf(address(router))];
    uint256[2] memory mainAddressBefore =
      [tokenIn.balanceOf(mainAddress), tokenOut.balanceOf(mainAddress)];
    uint256[2] memory feeReceiversBefore =
      [tokenIn.balanceOf(partnerRecipient), tokenOut.balanceOf(partnerRecipient)];

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);

    assertEq(tokenIn.balanceOf(address(router)), routerBefore[0]);
    assertEq(tokenOut.balanceOf(address(router)), routerBefore[1]);
    assertEq(tokenIn.balanceOf(mainAddress), mainAddressBefore[0] - amountIn);
    assertEq(tokenOut.balanceOf(mainAddress), mainAddressBefore[1] + params.returnAmount);
    assertEq(tokenIn.balanceOf(partnerRecipient), feeReceiversBefore[0] + beforeSwapFee);
    assertEq(tokenOut.balanceOf(partnerRecipient), feeReceiversBefore[1] + afterSwapFee);
  }

  function testConditionalSwapSuccess(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));

    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(
      intentData.tokenData, _adjustRecipient(feeAfter == 0 ? swapdata2 : swapdata), false
    );

    vm.warp(vm.getBlockTimestamp() + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function test_DCASwap_TimeBased(uint256 mode) public {
    mode = bound(mode, 0, 2);

    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](3);
    condition[0] =
      _timeCondition(((vm.getBlockTimestamp() - 100) << 128) | (vm.getBlockTimestamp() + 100));
    condition[1] =
      _timeCondition(((vm.getBlockTimestamp() + 500) << 128) | (vm.getBlockTimestamp() + 700));
    condition[2] =
      _timeCondition(((vm.getBlockTimestamp() + 1000) << 128) | (vm.getBlockTimestamp() + 1200));

    IntentData memory intentData;
    {
      uint256 tmpSwapAmount = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, condition);
      _setUpMainAddress(intentData, false);
      swapAmount = tmpSwapAmount;
    }

    ActionData memory actionData = _mockSwapAction();

    _swap(mode, intentData, actionData, 0, 0);

    vm.warp(vm.getBlockTimestamp() + 500);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 0, 1);

    vm.warp(vm.getBlockTimestamp() + 600);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 0, 2);
  }

  function test_DCASwap_PriceBased(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);
    condition[0] = KSConditionalSwapHook.SwapCondition({
      swapLimit: 4,
      timeLimits: (0 << 128) | type(uint128).max,
      amountInLimits: (swapAmount << 128) | swapAmount,
      maxFees: (0 << 128) | type(uint128).max,
      priceLimits: ((1_000_000_000_000 - 100) << 128) | (1_000_000_000_000 + 100),
      oracle: _noOracle()
    });

    IntentData memory intentData;
    {
      uint256 tmpSwapAmount = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, condition);
      _setUpMainAddress(intentData, false);
      swapAmount = tmpSwapAmount;
    }
    ActionData memory actionData = _mockSwapAction();

    _swap(mode, intentData, actionData, 0, 0);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 1, 0);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 2, 0);
  }

  function testRevert_InvalidTimeCondition(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);
    condition[0] =
      _timeCondition(((vm.getBlockTimestamp() + 100) << 128) | (vm.getBlockTimestamp() + 1000));

    IntentData memory intentData = _getIntentData(0, type(uint128).max, condition);
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(
      intentData.tokenData, _adjustRecipient(feeAfter == 0 ? swapdata2 : swapdata), false
    );

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_InvalidPriceCondition(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);
    condition[0] = KSConditionalSwapHook.SwapCondition({
      swapLimit: 1,
      timeLimits: ((vm.getBlockTimestamp() - 100) << 128) | (vm.getBlockTimestamp() + 100),
      amountInLimits: (0 << 128) | type(uint128).max,
      maxFees: (0 << 128) | type(uint128).max,
      priceLimits: (uint256(type(uint128).max) << 128) | type(uint128).max,
      oracle: _noOracle()
    });

    IntentData memory intentData = _getIntentData(0, type(uint128).max, condition);
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(
      intentData.tokenData, _adjustRecipient(feeAfter == 0 ? swapdata2 : swapdata), false
    );

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_ExceedSwapLimit(uint256 mode) public {
    mode = bound(mode, 0, 2);
    uint256 tmpSwapAmount = swapAmount;
    swapAmount = type(uint256).max;
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);
    swapAmount = tmpSwapAmount;
    ActionData memory actionData;
    {
      TokenData memory tokenData;
      tokenData.erc20Data = new ERC20Data[](1);
      tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
      actionData = _getActionData(tokenData, '', true);
    }

    bytes32 hash = router.hashTypedIntentData(intentData);
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, 0), 0);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    actionData.nonce += 1;
    (caller, dkSignature, gdSignature) = _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);

    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, 0), 1);
  }

  function testRevert_InvalidTokenIn(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);
    intentData.tokenData.erc20Data[0].token = makeAddr('dummy');
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(
      intentData.tokenData, _adjustRecipient(feeAfter == 0 ? swapdata2 : swapdata), false
    );
    actionData.erc20Ids[0] = 0;

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        KSConditionalSwapHook.InvalidTokenIn.selector, makeAddr('dummy'), tokenIn
      )
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_AmountInTooSmallOrTooLarge(uint256 mode, uint128 min, uint128 max) public {
    mode = bound(mode, 0, 2);
    vm.assume(min < max && (min > swapAmount || max < swapAmount));
    IntentData memory intentData =
      _getIntentData(min, max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(
      intentData.tokenData, _adjustRecipient(feeAfter == 0 ? swapdata2 : swapdata), false
    );

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_ExceedFeeLimit(uint256 mode) public {
    feeBefore = 1000;
    feeAfter = 1000;

    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);

    uint256 beforeSwapFee = (swapAmount * feeBefore) / 1_000_000;

    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(tokenIn, tokenOut, swapAmount - beforeSwapFee, 1000, address(router), mainAddress),
      true
    );

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function test_Chainlink_MarketTrigger_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleLib.OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _band(USDT_USD, 100, 100)),
      _chainlinkLeg(address(feedOut), _band(BTC_USD, 100, 100)),
      0
    );
    _expectSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO), 0, new bytes[](0));
  }

  function test_Chainlink_MarketTrigger_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    // tokenOut band sits entirely above the live BTC price -> never met
    OracleLib.OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _band(USDT_USD, 100, 100)),
      _chainlinkLeg(address(feedOut), (uint256(BTC_USD * 2) << 128) | type(uint128).max),
      0
    );
    _expectSwapRevert(mode, cfg, _amountOutFor(ORACLE_RATIO), 0, new bytes[](0));
  }

  function test_Chainlink_SlippageGuard_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleLib.OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), FULL_BAND),
      _chainlinkLeg(address(feedOut), FULL_BAND),
      _params(0, 1000) // 10% tolerance
    );
    _expectSwapOk(mode, cfg, _amountOutFor((ORACLE_RATIO * 105) / 100), 0, new bytes[](0)); // +5%
  }

  function test_Chainlink_SlippageGuard_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleLib.OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), FULL_BAND),
      _chainlinkLeg(address(feedOut), FULL_BAND),
      _params(0, 100) // 1% tolerance
    );
    _expectSwapRevert(mode, cfg, _amountOutFor((ORACLE_RATIO * 105) / 100), 0, new bytes[](0)); // +5%
  }

  function test_Chainlink_SingleLeg_Out(uint256 mode) public {
    mode = bound(mode, 0, 2);
    // only the output token is constrained; the input leg is left unconfigured
    OracleLib.OracleConfig memory cfg =
      _config(_emptyLeg(), _chainlinkLeg(address(feedOut), _band(BTC_USD, 100, 100)), 0);
    _expectSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO), 0, new bytes[](0));
  }

  function test_Pyth_Update_And_Validate(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleLib.OracleConfig memory cfg = _config(
      _pythLeg(address(pyth), USDT_ID, _band(USDT_USD, 100, 100)),
      _pythLeg(address(pyth), WBTC_ID, _band(BTC_USD, 100, 100)),
      _params(3600, 0)
    );

    uint256 hookBalBefore = address(conditionalSwapHook).balance;
    (IntentData memory intentData, ActionData memory actionData) = _buildIntentAndAction(
      _single(cfg), _amountOutFor(ORACLE_RATIO), 0, _pythUpdateData(vm.getBlockTimestamp())
    );

    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeSwap(mode, intentData, actionData);

    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
    assertEq(pyth.updateCount(), 1); // hook pushed exactly one update
    assertEq(address(pyth).balance, PYTH_FEE); // fee delivered to Pyth
    assertEq(address(conditionalSwapHook).balance, hookBalBefore - PYTH_FEE); // paid by the hook
  }

  function test_Pyth_StalePrice_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleLib.OracleConfig memory cfg = _config(
      _pythLeg(address(pyth), USDT_ID, FULL_BAND),
      _pythLeg(address(pyth), WBTC_ID, FULL_BAND),
      _params(100, 0) // 100s staleness bound
    );
    // publish time well in the past -> getPriceNoOlderThan reverts during afterExecution
    vm.warp(vm.getBlockTimestamp() + 1000);
    bytes[] memory updateData = _pythUpdateData(vm.getBlockTimestamp() - 1000);

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ORACLE_RATIO), 0, updateData);

    (address caller, bytes memory dk, bytes memory gd) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectRevert(MockPyth.StalePrice.selector);
    router.execute(intentData, dk, guardian, gd, actionData);
  }

  /// @dev Two conditions, each with its own oracle (Chainlink then Pyth) in one intent index.
  function test_PerCondition_IndependentOracles(uint256 mode) public {
    mode = bound(mode, 0, 2);

    KSConditionalSwapHook.SwapCondition[] memory conditions =
      new KSConditionalSwapHook.SwapCondition[](2);
    // condition 0: Chainlink, tokenOut band above the live price -> never matches
    conditions[0] = _oracleCondition(
      _config(
        _chainlinkLeg(address(feedIn), _band(USDT_USD, 100, 100)),
        _chainlinkLeg(address(feedOut), (uint256(BTC_USD * 2) << 128) | type(uint128).max),
        0
      )
    );
    // condition 1: Pyth, bands bracket the live prices -> matches
    conditions[1] = _oracleCondition(
      _config(
        _pythLeg(address(pyth), USDT_ID, _band(USDT_USD, 100, 100)),
        _pythLeg(address(pyth), WBTC_ID, _band(BTC_USD, 100, 100)),
        _params(3600, 0)
      )
    );

    // oracleUpdateIndex = 1 -> refresh uses condition 1's (Pyth) config
    (IntentData memory intentData, ActionData memory actionData) = _buildIntentAndAction(
      conditions, _amountOutFor(ORACLE_RATIO), 1, _pythUpdateData(vm.getBlockTimestamp())
    );

    bytes32 hash = router.hashTypedIntentData(intentData);
    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeSwap(mode, intentData, actionData);

    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, 0), 0);
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, 1), 1);
  }

  function test_Fork_ChainlinkReal_MarketTrigger_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    (uint256 priceIn, uint256 priceOut, uint256 ratio) =
      _readReal(_realChainlink(FULL_BAND, FULL_BAND));

    OracleLib.OracleConfig memory cfg =
      _realChainlink(_band(priceIn, 100, 100), _band(priceOut, 100, 100));
    _expectSwapOk(mode, cfg, _amountOutFor(ratio), 0, new bytes[](0));
  }

  function test_Fork_ChainlinkReal_MarketTrigger_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    (, uint256 priceOut, uint256 ratio) = _readReal(_realChainlink(FULL_BAND, FULL_BAND));

    OracleLib.OracleConfig memory cfg =
      _realChainlink(FULL_BAND, (uint256(priceOut * 2) << 128) | type(uint128).max);
    _expectSwapRevert(mode, cfg, _amountOutFor(ratio), 0, new bytes[](0));
  }

  function test_Fork_ChainlinkReal_SlippageGuard_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    (,, uint256 ratio) = _readReal(_realChainlink(FULL_BAND, FULL_BAND));

    OracleLib.OracleConfig memory cfg = _realChainlink(FULL_BAND, FULL_BAND);
    cfg.oracleParams = _params(0, 200); // 2% tolerance
    _expectSwapRevert(mode, cfg, _amountOutFor((ratio * 110) / 100), 0, new bytes[](0)); // +10%
  }

  function test_Fork_PythReal_Read_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    (uint256 priceIn, uint256 priceOut, uint256 ratio) = _readReal(_realPyth(FULL_BAND, FULL_BAND));

    OracleLib.OracleConfig memory cfg =
      _realPyth(_band(priceIn, 200, 200), _band(priceOut, 200, 200));
    _expectSwapOk(mode, cfg, _amountOutFor(ratio), 0, new bytes[](0));
  }

  function test_Fork_PythReal_Update_Pass() public {
    bytes[] memory updateData = new bytes[](1);
    updateData[0] = pythUpdateData;

    (uint256 priceIn, uint256 priceOut, uint256 ratio) = _readReal(_realPyth(FULL_BAND, FULL_BAND));
    OracleLib.OracleConfig memory cfg =
      _realPyth(_band(priceIn, 200, 200), _band(priceOut, 200, 200));

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ratio), 0, updateData);

    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeSwap(1, intentData, actionData);
    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
  }

  function test_Fork_RealSwap_ChainlinkChainlink_Pass(uint256 mode) public {
    _runRealSwapOracle(mode, false, false, true);
  }

  function test_Fork_RealSwap_ChainlinkChainlink_Fail(uint256 mode) public {
    _runRealSwapOracle(mode, false, false, false);
  }

  function test_Fork_RealSwap_PythPyth_Pass(uint256 mode) public {
    _runRealSwapOracle(mode, true, true, true);
  }

  function test_Fork_RealSwap_PythPyth_Fail(uint256 mode) public {
    _runRealSwapOracle(mode, true, true, false);
  }

  function test_Fork_RealSwap_ChainlinkPyth_Pass(uint256 mode) public {
    _runRealSwapOracle(mode, false, true, true);
  }

  function test_Fork_RealSwap_ChainlinkPyth_Fail(uint256 mode) public {
    _runRealSwapOracle(mode, false, true, false);
  }

  function test_Fork_RealSwap_PythChainlink_Pass(uint256 mode) public {
    _runRealSwapOracle(mode, true, false, true);
  }

  function test_Fork_RealSwap_PythChainlink_Fail(uint256 mode) public {
    _runRealSwapOracle(mode, true, false, false);
  }

  function _runRealSwapOracle(uint256 mode, bool inPyth, bool outPyth, bool ok) internal {
    mode = bound(mode, 0, 2);

    // read the live per-leg USD prices (read-only; Pyth legs are already on-chain at the fork)
    (uint256 priceIn, uint256 priceOut,) =
      _readReal(_config(_legIn(inPyth, FULL_BAND), _legOut(outPyth, FULL_BAND), 0));

    uint256 bandOut =
      ok ? _band(priceOut, 100, 100) : (uint256(priceOut * 2) << 128) | type(uint128).max;

    OracleLib.OracleConfig memory cfg = _config(
      _legIn(inPyth, _band(priceIn, 100, 100)),
      _legOut(outPyth, bandOut),
      _params(0, 1000) // 10% slippage tolerance (live price vs the captured route)
    );

    bytes[] memory updateData = new bytes[](0);
    if (inPyth || outPyth) {
      updateData = new bytes[](1);
      updateData[0] = pythUpdateData;
    }

    KSConditionalSwapHook.SwapCondition[] memory condition = _single(cfg);
    IntentData memory intentData = _getIntentData(0, type(uint128).max, condition);
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(
      intentData.tokenData, _adjustRecipient(feeAfter == 0 ? swapdata2 : swapdata), false
    );
    // oracleUpdateIndex = 0 (single condition); supply the real Pyth blob when any leg is Pyth
    actionData.hookActionData =
      abi.encode(uint256(0), (feeBefore << 128) | feeAfter, uint256(0), updateData);

    (address caller, bytes memory dk, bytes memory gd) =
      _getCallerAndSignatures(mode, intentData, actionData);

    if (!ok) {
      vm.startPrank(caller);
      vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
      router.execute(intentData, dk, guardian, gd, actionData);
      return;
    }

    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    vm.startPrank(caller);
    router.execute(intentData, dk, guardian, gd, actionData);
    vm.stopPrank();
    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
  }

  function _legIn(bool pyth_, uint256 band) internal pure returns (OracleLib.TokenOracle memory) {
    return
      pyth_ ? _pythLeg(PYTH_MAINNET, PYTH_USDT_USD, band) : _chainlinkLeg(CHAINLINK_USDT_USD, band);
  }

  function _legOut(bool pyth_, uint256 band) internal pure returns (OracleLib.TokenOracle memory) {
    return
      pyth_ ? _pythLeg(PYTH_MAINNET, PYTH_BTC_USD, band) : _chainlinkLeg(CHAINLINK_WBTC_USD, band);
  }

  /// @dev Chainlink and Pyth agree on the live BTC price within 1%.
  function test_Fork_RealOracles_Agree() public view {
    (,, uint256 clRatio) = _readReal(_realChainlink(FULL_BAND, FULL_BAND));
    (,, uint256 pythRatio) = _readReal(_realPyth(FULL_BAND, FULL_BAND));
    uint256 diff = clRatio > pythRatio ? clRatio - pythRatio : pythRatio - clRatio;
    assertLt(diff * 10_000, clRatio * 100);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  function _realChainlink(uint256 bandIn, uint256 bandOut)
    internal
    pure
    returns (OracleLib.OracleConfig memory)
  {
    return _config(
      _chainlinkLeg(CHAINLINK_USDT_USD, bandIn), _chainlinkLeg(CHAINLINK_WBTC_USD, bandOut), 0
    );
  }

  function _realPyth(uint256 bandIn, uint256 bandOut)
    internal
    pure
    returns (OracleLib.OracleConfig memory)
  {
    return _config(
      _pythLeg(PYTH_MAINNET, PYTH_USDT_USD, bandIn),
      _pythLeg(PYTH_MAINNET, PYTH_BTC_USD, bandOut),
      0
    );
  }

  function _readReal(OracleLib.OracleConfig memory cfg)
    internal
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    return OracleLib.getPrices(cfg, tokenIn, tokenOut);
  }

  function _oracleCondition(OracleLib.OracleConfig memory oracle)
    internal
    pure
    returns (KSConditionalSwapHook.SwapCondition memory)
  {
    return KSConditionalSwapHook.SwapCondition({
      swapLimit: 4,
      timeLimits: (0 << 128) | type(uint128).max,
      amountInLimits: (0 << 128) | type(uint128).max,
      maxFees: (0 << 128) | type(uint128).max,
      priceLimits: (0 << 128) | type(uint128).max,
      oracle: oracle
    });
  }

  function _single(OracleLib.OracleConfig memory oracle)
    internal
    pure
    returns (KSConditionalSwapHook.SwapCondition[] memory conditions)
  {
    conditions = new KSConditionalSwapHook.SwapCondition[](1);
    conditions[0] = _oracleCondition(oracle);
  }

  function _timeCondition(uint256 timeLimits)
    internal
    view
    returns (KSConditionalSwapHook.SwapCondition memory)
  {
    return KSConditionalSwapHook.SwapCondition({
      swapLimit: 1,
      timeLimits: timeLimits,
      amountInLimits: (swapAmount << 128) | swapAmount,
      maxFees: (0 << 128) | type(uint128).max,
      priceLimits: (0 << 128) | type(uint128).max,
      oracle: _noOracle()
    });
  }

  /// @dev amountOut that yields a realized price of `realizedPrice` for amountIn == swapAmount.
  function _amountOutFor(uint256 realizedPrice) internal view returns (uint256) {
    return (realizedPrice * swapAmount) / 1e18;
  }

  function _pythUpdateData(uint256 publishTime) internal pure returns (bytes[] memory updateData) {
    updateData = new bytes[](2);
    updateData[0] = abi.encode(USDT_ID, int64(1e8), int32(-8), publishTime);
    updateData[1] = abi.encode(WBTC_ID, int64(int256(100_000e8)), int32(-8), publishTime);
  }

  function _mockSwapAction() internal view returns (ActionData memory actionData) {
    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
    actionData = _getActionData(
      tokenData,
      abi.encode(
        tokenIn,
        tokenOut,
        swapAmount,
        1000,
        feeAfter == 0 ? mainAddress : address(router),
        mainAddress
      ),
      true
    );
  }

  function _buildIntentAndAction(
    KSConditionalSwapHook.SwapCondition[] memory conditions,
    uint256 amountOut,
    uint256 oracleUpdateIndex,
    bytes[] memory updateData
  ) internal returns (IntentData memory intentData, ActionData memory actionData) {
    {
      uint256 tmp = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, conditions);
      _setUpMainAddress(intentData, false);
      swapAmount = tmp;
    }

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});

    actionData = _getActionData(
      tokenData,
      abi.encode(tokenIn, tokenOut, swapAmount, amountOut, mainAddress, mainAddress),
      true
    );
    actionData.hookActionData = abi.encode(uint256(0), uint256(0), oracleUpdateIndex, updateData);
  }

  function _expectSwapOk(
    uint256 mode,
    OracleLib.OracleConfig memory cfg,
    uint256 amountOut,
    uint256 oracleUpdateIndex,
    bytes[] memory updateData
  ) internal {
    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), amountOut, oracleUpdateIndex, updateData);
    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeSwap(mode, intentData, actionData);
    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
  }

  function _expectSwapRevert(
    uint256 mode,
    OracleLib.OracleConfig memory cfg,
    uint256 amountOut,
    uint256 oracleUpdateIndex,
    bytes[] memory updateData
  ) internal {
    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), amountOut, oracleUpdateIndex, updateData);
    (address caller, bytes memory dk, bytes memory gd) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, dk, guardian, gd, actionData);
  }

  function _executeSwap(uint256 mode, IntentData memory intentData, ActionData memory actionData)
    internal
  {
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    vm.stopPrank();
  }

  function _swap(
    uint256 mode,
    IntentData memory intentData,
    ActionData memory actionData,
    uint256 swapCount,
    uint256 index
  ) internal {
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);
    bytes32 hash = router.hashTypedIntentData(intentData);

    uint256 balanceBefore = tokenOut.balanceOf(mainAddress);

    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, index), swapCount);
    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    vm.stopPrank();
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, index), swapCount + 1);

    assertGt(tokenOut.balanceOf(mainAddress), balanceBefore);
  }

  function _getActionData(TokenData memory tokenData, bytes memory actionCalldata, bool swapViaMock)
    internal
    view
    returns (ActionData memory actionData)
  {
    FeeInfo memory feeInfo;
    feeInfo.protocolRecipient = protocolRecipient;
    feeInfo.partnerFeeConfigs = new FeeConfig[][](1);
    feeInfo.partnerFeeConfigs[0] = _buildPartnersConfigs(
      PartnersFeeConfigBuildParams({
        feeModes: [false].toMemoryArray(),
        partnerFees: [uint24(1e6)].toMemoryArray(),
        partnerRecipients: [partnerRecipient].toMemoryArray()
      })
    );

    actionData = ActionData({
      erc20Ids: [uint256(0)].toMemoryArray(),
      erc20Amounts: [tokenData.erc20Data[0].amount].toMemoryArray(),
      erc721Ids: new uint256[](0),
      feeInfo: feeInfo,
      approvalFlags: (1 << (tokenData.erc20Data.length + tokenData.erc721Data.length)) - 1,
      actionSelectorId: swapViaMock ? 0 : 1,
      actionCalldata: swapViaMock
        ? (actionCalldata.length == 0
            ? abi.encode(
              tokenIn,
              tokenOut,
              swapAmount,
              1000,
              feeAfter == 0 ? mainAddress : address(router),
              mainAddress
            )
            : actionCalldata)
        : actionCalldata,
      hookActionData: abi.encode(
        uint256(0), (feeBefore << 128) | feeAfter, uint256(0), new bytes[](0)
      ),
      extraData: '',
      deadline: vm.getBlockTimestamp() + 1 days,
      nonce: 0
    });
  }

  function _getIntentData(
    uint256 min,
    uint256 max,
    KSConditionalSwapHook.SwapCondition[] memory swapConditions
  ) internal view returns (IntentData memory intentData) {
    KSConditionalSwapHook.SwapHookData memory hookData;
    hookData.srcTokens = [tokenIn].toMemoryArray();
    hookData.dstTokens = [tokenOut].toMemoryArray();
    hookData.recipient = mainAddress;
    hookData.swapConditions = new KSConditionalSwapHook.SwapCondition[][](1);

    if (swapConditions.length > 0) {
      hookData.swapConditions[0] = swapConditions;
    } else {
      hookData.swapConditions[0] = new KSConditionalSwapHook.SwapCondition[](1);
      hookData.swapConditions[0][0] = KSConditionalSwapHook.SwapCondition({
        swapLimit: 1,
        timeLimits: (vm.getBlockTimestamp() << 128) | (vm.getBlockTimestamp() + 1 days),
        amountInLimits: (min << 128) | max,
        maxFees: (maxSrcFee << 128) | maxDstFee,
        priceLimits: (0 << 128) | type(uint128).max,
        oracle: _noOracle()
      });
    }

    intentData.coreData.mainAddress = mainAddress;
    intentData.coreData.signatureVerifier = address(0);
    intentData.coreData.delegatedKey = delegatedPublicKey;
    intentData.coreData.actionContracts =
      [address(mockActionContract), address(swapRouter)].toMemoryArray();
    intentData.coreData.actionSelectors =
      [MockActionContract.swap.selector, IKSSwapRouterV2.swap.selector].toMemoryArray();
    intentData.coreData.hook = address(conditionalSwapHook);
    intentData.coreData.hookIntentData = abi.encode(hookData);

    intentData.tokenData.erc20Data = new ERC20Data[](1);
    intentData.tokenData.erc20Data[0] =
      ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
  }

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent) internal {
    vm.startPrank(mainAddress);
    IERC20(tokenIn).safeIncreaseAllowance(address(router), type(uint256).max);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    vm.stopPrank();
  }

  function _adjustRecipient(bytes memory data) internal view returns (bytes memory) {
    IKSSwapRouterV2.SwapExecutionParams memory params =
      abi.decode(data, (IKSSwapRouterV2.SwapExecutionParams));

    params.desc.dstReceiver = feeAfter == 0 ? mainAddress : address(router);

    return abi.encode(params);
  }
}
