Feature: Search
  Scenario: Find field by field_name
    Given I have the following fields:
      | field_name |
      | Creator    |
      | Field1     |
      | Field2     |
    When I search for Field
    Then the results should be:
      | field_name |
      | Field1     |
      | Field2     |
