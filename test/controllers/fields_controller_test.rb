require 'test_helper'

class FieldsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @field = fields(:one)
  end

  test "should get index" do
    get fields_url
    assert_response :success
  end

  test "should get new" do
    get new_field_url
    assert_response :success
  end

  test "should create field" do
    assert_difference('Field.count') do
      post fields_url, params: { field: { description: @field.description, example_data: @field.example_data, name: @field.field_name, public_interface_label: @field.public_interface_label, staff_interface_label: @field.staff_interface_label, system_generated: @field.system_generated, system_required: @field.system_required, table: @field.field_table, type: @field.field_type } }
    end

    assert_redirected_to field_url(Field.last)
  end

  test "should show field" do
    get field_url(@field)
    assert_response :success
  end

  test "should get edit" do
    get edit_field_url(@field)
    assert_response :success
  end

  test "should update field" do
    patch field_url(@field), params: { field: { description: @field.description, example_data: @field.example_data, name: @field.field_name, public_interface_label: @field.public_interface_label, staff_interface_label: @field.staff_interface_label, system_generated: @field.system_generated, system_required: @field.system_required, table: @field.field_table, type: @field.field_type } }
    assert_redirected_to field_url(@field)
  end

  test "should destroy field" do
    assert_difference('Field.count', -1) do
      delete field_url(@field)
    end

    assert_redirected_to fields_url
  end
end
