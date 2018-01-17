require 'factory_bot'

FactoryBot.define do
  factory :creator, class: Field do
    field_name 'Creator'
  end
  factory :field1, class: Field do
    field_name 'Field1'
  end
  factory :field2, class: Field do
    field_name 'Field2'
  end
end
