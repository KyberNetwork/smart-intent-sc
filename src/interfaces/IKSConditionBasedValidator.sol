// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

type ConditionType is bytes32;

interface IKSConditionBasedValidator {
  error ConditionsNotMet();

  /**
   * @param conditionType the type of the condition
   * @param data the data of the condition
   */
  struct Condition {
    ConditionType conditionType;
    bytes data;
  }

  /**
   * @dev 2D array for logical expressions represented in Disjunctive Normal Form
   * Example: (A and B) or (C and D and E) = [[A,B], [C,D,E]]
   * @param conditions the conditions to be validated
   */
  struct DNFExpression {
    Condition[][] conditions;
  }

  /**
   * @param dnfExpression the DNF expression to be validated
   * @param additionalData the additional data to be validated or used for validation
   * @return true if the conditions are met, false otherwise
   */
  function validateConditions(DNFExpression calldata dnfExpression, bytes calldata additionalData)
    external
    view
    returns (bool);
}
