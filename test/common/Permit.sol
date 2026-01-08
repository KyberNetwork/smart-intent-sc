// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC721Permit_v3} from 'ks-common-sc/src/libraries/token/PermitHelper.sol';

library Permit {
  function uniswapV4Permit(
    address positionManager,
    address spender,
    uint256 tokenId,
    uint256 nonce,
    uint256 deadline
  ) external view returns (bytes32 digest) {
    return hashTypedData(positionManager, hashPermit(spender, tokenId, nonce, deadline));
  }

  function hashPermit(address spender, uint256 tokenId, uint256 nonce, uint256 deadline)
    internal
    pure
    returns (bytes32 digest)
  {
    // equivalent to: keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, nonce, deadline));
    bytes32 permitTypeHash = 0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;
    assembly ('memory-safe') {
      let fmp := mload(0x40)
      mstore(fmp, permitTypeHash)
      mstore(add(fmp, 0x20), and(spender, 0xffffffffffffffffffffffffffffffffffffffff))
      mstore(add(fmp, 0x40), tokenId)
      mstore(add(fmp, 0x60), nonce)
      mstore(add(fmp, 0x80), deadline)
      digest := keccak256(fmp, 0xa0)

      // now clean the memory we used
      mstore(fmp, 0) // fmp held PERMIT_TYPEHASH
      mstore(add(fmp, 0x20), 0) // fmp+0x20 held spender
      mstore(add(fmp, 0x40), 0) // fmp+0x40 held tokenId
      mstore(add(fmp, 0x60), 0) // fmp+0x60 held nonce
      mstore(add(fmp, 0x80), 0) // fmp+0x80 held deadline
    }
  }

  function hashTypedData(address positionManager, bytes32 dataHash)
    internal
    view
    returns (bytes32 digest)
  {
    // equal to keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), dataHash));
    bytes32 domainSeparator = IERC721Permit_v3(positionManager).DOMAIN_SEPARATOR();
    assembly ('memory-safe') {
      let fmp := mload(0x40)
      mstore(fmp, hex'1901')
      mstore(add(fmp, 0x02), domainSeparator)
      mstore(add(fmp, 0x22), dataHash)
      digest := keccak256(fmp, 0x42)

      // now clean the memory we used
      mstore(fmp, 0) // fmp held "\x19\x01", domainSeparator
      mstore(add(fmp, 0x20), 0) // fmp+0x20 held domainSeparator, dataHash
      mstore(add(fmp, 0x40), 0) // fmp+0x40 held dataHash
    }
  }
}
