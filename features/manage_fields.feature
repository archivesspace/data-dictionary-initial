Feature: Manage Fields
  In order to understand the data model for ArchivesSpace
  As an archivist or ArchivesSpace community member
  I want to manage fields

  Scenario: Fields List
    Given I have a field named Creator
    When I go to the list of fields
    Then I should see "Creator"

# Field name:string type:string table:string description:text staff_interface_label:string
# public_interface_label:string system_required:boolean system_generated:boolean example_data:text
  Scenario: Modify Field Data
    Given I have fields
    And I am on the list of fields
    When I follow "Update Field"
    And I fill in "Description" with "Edited Description"
    And I press "Update Field"
    Then I should see "Field was successfully updated"
    And I should see "Edited Description"

  Scenario: Create Valid Field
    Given I have no fields
    And I am on the list of fields
#    When I press "Choose File"
#    And I fill in "File" with "test_data.xlsx"
    And I press "Import"
    Then I should see "Fields imported."
    And I should see "agent_family_id"
    And I should see "System generated"
    And I should have 66 fields
