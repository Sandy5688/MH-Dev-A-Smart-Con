// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IInstallmentLogic {
    function createInstallmentPlan(
        address _payer,
        address _payee,
        uint256 _totalAmount,
        uint256 _installmentCount
    ) external returns (uint256);

    function payInstallment(uint256 _planId, uint256 _amount) external;

    function getInstallmentPlan(
        uint256 _planId
    )
        external
        view
        returns (
            uint256 totalAmount,
            uint256 paidAmount,
            uint256 installmentCount,
            uint256 installmentsPaid,
            address payer,
            address payee,
            bool active
        );
}
