// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IInstallmentLogic.sol";

contract InstallmentLogic is IInstallmentLogic {
    struct InstallmentPlan {
        uint256 totalAmount;
        uint256 paidAmount;
        uint256 installmentCount;
        uint256 installmentsPaid;
        address payer;
        address payee;
        bool active;
    }

    uint256 private nextPlanId;
    mapping(uint256 => InstallmentPlan) private plans;

    event InstallmentPlanCreated(
        uint256 indexed planId,
        address indexed payer,
        address indexed payee,
        uint256 totalAmount,
        uint256 installmentCount
    );

    event InstallmentPaid(
        uint256 indexed planId,
        address indexed payer,
        uint256 amount,
        uint256 installmentsPaid
    );

    event InstallmentPlanCompleted(
        uint256 indexed planId,
        address indexed payer,
        address indexed payee
    );

    constructor() {
        nextPlanId = 1;
    }

    /// @notice Create a new installment plan
    function createInstallmentPlan(
        address _payer,
        address _payee,
        uint256 _totalAmount,
        uint256 _installmentCount
    ) external override returns (uint256) {
        require(_payer != address(0), "Invalid payer");
        require(_payee != address(0), "Invalid payee");
        require(_payer != _payee, "Payer and payee cannot be same");
        require(_totalAmount > 0, "Amount must be > 0");
        require(_installmentCount > 0, "Installment count must be > 0");

        uint256 planId = nextPlanId++;
        plans[planId] = InstallmentPlan({
            totalAmount: _totalAmount,
            paidAmount: 0,
            installmentCount: _installmentCount,
            installmentsPaid: 0,
            payer: _payer,
            payee: _payee,
            active: true
        });

        emit InstallmentPlanCreated(
            planId,
            _payer,
            _payee,
            _totalAmount,
            _installmentCount
        );

        return planId;
    }

    /// @notice Pay an installment for an existing plan
    function payInstallment(uint256 _planId, uint256 _amount) external override {
        InstallmentPlan storage plan = plans[_planId];
        require(plan.active, "Plan not active");
        require(msg.sender == plan.payer, "Only payer can pay");
        require(_amount > 0, "Amount must be > 0");
        require(plan.paidAmount + _amount <= plan.totalAmount, "Overpayment not allowed");

        plan.paidAmount += _amount;
        plan.installmentsPaid += 1;

        emit InstallmentPaid(_planId, msg.sender, _amount, plan.installmentsPaid);

        if (plan.paidAmount >= plan.totalAmount) {
            plan.active = false;
            emit InstallmentPlanCompleted(_planId, plan.payer, plan.payee);
        }
    }

    /// @notice Get details of an installment plan
    function getInstallmentPlan(
        uint256 _planId
    )
        external
        view
        override
        returns (
            uint256 totalAmount,
            uint256 paidAmount,
            uint256 installmentCount,
            uint256 installmentsPaid,
            address payer,
            address payee,
            bool active
        )
    {
        InstallmentPlan memory plan = plans[_planId];
        return (
            plan.totalAmount,
            plan.paidAmount,
            plan.installmentCount,
            plan.installmentsPaid,
            plan.payer,
            plan.payee,
            plan.active
        );
    }
}
