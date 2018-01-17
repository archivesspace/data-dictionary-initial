Feature: Manage Fields
  In order to understand the data model for ArchivesSpace
  As an archivist or ArchivesSpace community member
  I want to manage fields

  Scenario: Fields List
    Given I have a field named Creator
    When I go to the list of fields
    Then I should see "Creator"

  Scenario: Create Valid Field
    Given I have no fields
    And I am on the list of fields
    And I press "Import"
    Then I should see "Fields imported."
    And I should see "agent_family_id"
    And I should see "System generated"
    And I should have 64 fields
