// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Shared logic for BNPL and loan repayment schedules
library InstallmentLogic {
    struct InstallmentPlan {
        uint256 total;
        uint256 paid;
        uint8 installments;
        uint256 createdAt;
        uint256 deadline;
    }

    function createPlan(uint256 totalAmount, uint8 count) internal view returns (InstallmentPlan memory) {
        require(count > 0, "Invalid count");
        return InstallmentPlan({
            total: totalAmount,
            paid: 0,
            installments: count,
            createdAt: block.timestamp,
            deadline: block.timestamp + 30 days
        });
    }

    function payInstallment(InstallmentPlan storage plan, uint256 amount, uint256 nowTime)
        internal returns (uint256 remaining, bool isLate)
    {
        require(nowTime <= plan.deadline, "Payment too late");
        require(plan.paid + amount <= plan.total, "Overpayment");

        plan.paid += amount;
        remaining = plan.total - plan.paid;
        isLate = nowTime > plan.deadline;

        emit InstallmentPaid(amount, remaining, isLate);
    }

    function getStatus(InstallmentPlan storage plan, uint256 nowTime)
        internal view returns (uint256 remaining, bool defaulted)
    {
        remaining = plan.total - plan.paid;
        defaulted = nowTime > plan.deadline && remaining > 0;
    }

    event InstallmentPaid(uint256 amount, uint256 remaining, bool late);
}
