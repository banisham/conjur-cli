Feature: Update the password of the logged-in user

  Background:
    Given I load the policy:
    """
    - !user alice
    """
    And I login as "alice"

  @restore-login
  Scenario: A user can update her own password
    And I run `conjur user update_password` interactively
    Then I can type and confirm a new password

  @restore-login
  Scenario: The new password can be used to login
    And I run `conjur user update_password` interactively
    And I type and confirm a new password
    And I run `conjur authn login alice` interactively
    And I enter the password
    Then the exit status should be 0
