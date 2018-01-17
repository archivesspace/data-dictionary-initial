Given /^I have the following fields:$/ do |fields|
  fields_attributes = fields.hashes.map do |fields_attrs|
    FactoryBot.create(fields_attrs["field_name"].downcase.to_sym)
  end
end

When /^I search for (.+)$/ do |query|
  visit('/search')
  fill_in('query', with: query)
  click_button('Search')
end

Then /^the results should be:$/ do |expected_results|
  results = [['field_name']] + page.all('ol.results td[2]').map do |li|
    [li.text]
  end
 expected_results.diff!(results)
end
