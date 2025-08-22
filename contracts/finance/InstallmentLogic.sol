// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IInstallmentLogic.sol";

/**
 * @title InstallmentLogic
 * @dev Handles installment-based payments for BNPL and subscription features.
 */
contract InstallmentLogic is Ownable, IInstallmentLogic {
    struct InstallmentPlan {
        uint256 totalAmount;
        uint256 paidAmount;
        uint256 installmentCount;
        uint256 installmentsPaid;
        address payer;
        address payee;
        bool active;
    }

    uint256 public planCounter;
    mapping(uint256 => InstallmentPlan) public plans;

    event InstallmentCreated(
        uint256 indexed planId,
        address indexed payer,
        address indexed payee,
        uint256 totalAmount,
        uint256 installmentCount
    );

    event InstallmentPaid(
        uint256 indexed planId,
        uint256 amount,
        uint256 installmentsPaid
    );

    event InstallmentCompleted(uint256 indexed planId);

    /**
     * @notice Create a new installment plan
     */
    function createInstallmentPlan(
        address _payer,
        address _payee,
        uint256 _totalAmount,
        uint256 _installmentCount
    ) external override onlyOwner returns (uint256) {
        require(_installmentCount > 0, "Invalid installments");
        require(_totalAmount > 0, "Invalid amount");

        planCounter++;
        plans[planCounter] = InstallmentPlan({
            totalAmount: _totalAmount,
            paidAmount: 0,
            installmentCount: _installmentCount,
            installmentsPaid: 0,
            payer: _payer,
            payee: _payee,
            active: true
        });

        emit InstallmentCreated(
            planCounter,
            _payer,
            _payee,
            _totalAmount,
            _installmentCount
        );

        return planCounter;
    }

    /**
     * @notice Pay an installment
     */
    function payInstallment(uint256 _planId, uint256 _amount) external override {
        InstallmentPlan storage plan = plans[_planId];
        require(plan.active, "Plan not active");
        require(msg.sender == plan.payer, "Not authorized");
        require(
            plan.installmentsPaid < plan.installmentCount,
            "All installments paid"
        );
        require(_amount > 0, "Invalid amount");

        plan.paidAmount += _amount;
        plan.installmentsPaid++;

        emit InstallmentPaid(_planId, _amount, plan.installmentsPaid);

        if (plan.installmentsPaid >= plan.installmentCount) {
            plan.active = false;
            emit InstallmentCompleted(_planId);
        }
    }

    /**
     * @notice Get details of an installment plan
     */
    function getInstallmentPlan(
        uint256 _planId
    ) external view override returns (InstallmentPlan memory) {
        return plans[_planId];
    }
}
