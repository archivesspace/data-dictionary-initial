Given /^I have a field named (.+)$/ do |name|
  FactoryBot.create(:creator_field)
end

When /^I go to (.+)$/ do |page_name|
  visit path_to(page_name)
end

Then /^I should see "([^\"]*)"$/ do |string|
  expect(page).to have_content string
end

Given /^I have fields$/ do
  FactoryBot.create(:creator_field)
  FactoryBot.create(:field1)
  FactoryBot.create(:field2)
end

Given /^I am on (.+)$/ do |page_name|
  visit path_to(page_name)
end

When /^I follow "([^\"]*)"$/ do |link|
#  click_link(link)
  first(:link, link).click
end

When /^I fill in "([^\"]*)" with "([^\"]*)"$/ do |field, value|
  fill_in(field, with: value)
end

When /^I press "([^\"]*)"$/ do |button|
  attach_file(:file, File.join(File.dirname(__FILE__), '../', 'upload-files', 'test_data.xlsx')) if button == "Import"
  click_button(button)
end

Given /^I have no fields$/ do
  Field.delete_all
end

Then /^I should have ([0-9]+) fields?$/ do |count|
  expect(Field.count).to eq(count.to_i)
end

Then /^I should see the field$/ do
  pending # Write code here that turns the phrase above into concrete actions
end
