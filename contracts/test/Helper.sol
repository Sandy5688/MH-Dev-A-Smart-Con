// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Helper {
    bool public called;

    function setCalled(bool _called) external {
        called = _called;
    }
}
