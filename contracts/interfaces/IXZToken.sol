// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IXZToken {
    function burnStrategicViaOracle(uint256 amount) external;
}
