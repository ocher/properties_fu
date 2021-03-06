require 'rubygems'
require 'active_record'
require 'active_record/test_case'
require 'active_record/fixtures'

require 'test/unit'
require File.dirname(__FILE__) + '/../init'

ActiveRecord::Base.establish_connection({
  :adapter => 'sqlite3', :database => ':memory:'
})
# this is VERY important! during setting up fixtures there is checked if ActiveRecord::Base.configurations is not blank.
ActiveRecord::Base.configurations = {:test => true}

ActiveRecord::Schema.define do
  create_table "users", :force => true do |t|
    t.column "name",  :string
    t.column "email", :string
  end

  create_table "user_properties", :force => true do |t|
    t.column 'resource_id', :integer
    t.column 'name', :string
    t.column 'value', :string
  end
end

class AbstractUser < ActiveRecord::Base
  set_table_name 'users'
  properties_fu :user_properties
end

class User < AbstractUser
  properties_fu :user_properties, :street, :city
end

class UserWithValidation < AbstractUser
  properties_fu :user_properties, :street, :city
  validates_presence_of :street
end


class PropertiesFuTest < ActiveSupport::TestCase
  include ActiveRecord::TestFixtures

  self.fixture_path = File.join(File.dirname(__FILE__), 'fixtures')
  # self.fixture_table_names = ActiveRecord::Base.connection.tables
  self.use_transactional_fixtures = true
  fixtures :users, :user_properties

  def setup
    @tim = users(:tim)
    @tim_street = user_properties(:tim_street)
    @tim_city = user_properties(:tim_city)
  end

  def test_should_define_userproperty_class
    assert_nothing_thrown { 'UserProperty'.constantize }
    property = UserProperty.new
    assert_equal nil, property.is_changed
    property.is_changed = true
    assert_equal true, property.is_changed
  end

  def test_should_define_has_many_relation_with_properties_table
    properties = @tim.user_properties
    assert_equal(2, properties.size)
    assert properties.include?(@tim_street)
    assert properties.include?(@tim_city)
  end

  def test_should_destroy_properties_during_destroying_object
    count = UserProperty.count
    @tim.destroy
    assert_equal(count - 2, UserProperty.count)
  end

  def test_should_define_properties_table_hash
    assert_equal(2, @tim.user_properties_hash.size)
    assert_equal @tim_street, @tim.user_properties_hash['street']
    assert_equal @tim_city, @tim.user_properties_hash['city']
  end

  def test_should_define_getter_metods_for_each_property
    assert_equal @tim_street.value, @tim.street
    assert_equal @tim_city.value, @tim.city
  end

  def test_should_define_setter_methods_for_properties
    assert_nothing_thrown { @tim.street = 'new street' }
    assert_equal 'new street', @tim.street
    assert_equal true, @tim.user_properties_hash['street'].is_changed
    @tim_street.reload                                    # check if property hasn't been saved
    assert_not_equal @tim_street.value, 'new_street'
  end

  def test_should_save_changed_properties
    @tim.street = 'new street'
    @tim.save
    @tim_street.reload
    assert_equal 'new street', @tim_street.value
  end

  def test_should_allow_setting_properties_for_a_new_object
    count = UserProperty.count
    user = User.new :name => 'marry', :email => 'marry@email.com'
    user.street = 'Blue Road'
    user.save
    assert_equal(count + 2, UserProperty.count)     # should create rows for initialized and uninitialized properties
    property = UserProperty.find(:first, :conditions => "resource_id = #{user.id} AND name = 'street'")
    assert_not_nil(property)                            # check if property has been saved with proper resource_id (defined in after_save hook)
    assert_equal('street', property.name)
    assert_equal('Blue Road', property.value)
    property = UserProperty.find(:first, :conditions => "resource_id = #{user.id} AND name = 'city'")
    assert_not_nil(property)                            # check if property has been saved with proper resource_id (defined in after_save hook)
    assert_equal('city', property.name)
    assert_equal(nil, property.value)


    # define a new property
    user.city = 'London'
    user.save
    assert_equal(count + 2, UserProperty.count)

    # update existing property
    user.city = 'Paris'
    user.save
    assert_equal(count + 2, UserProperty.count)     # number of properties remains the same
  end

  def test_should_create_rows_for_not_initialized_properties_after_create
    count = UserProperty.count
    user = User.new
    user.save
    assert_equal(count + 2, UserProperty.count)     # should create two properties
  end

  def test_should_check_if_validation_and_getting_value_of_not_saved_property_works_properly
    user = UserWithValidation.new :name => 'marry', :email => 'marry@email.com'
    assert_equal(false, user.save)
    assert_not_nil(user.errors.on(:street))
  end

  def test_should_return_defined_properties_list_for_a_class
    assert_equal([], AbstractUser.user_properties_list)
    assert_equal([:street, :city], User.user_properties_list)
  end

  def test_should_provide_method_for_building_join_statements
    # should allow join statement with no parameters
    assert_equal('', User.user_properties_joins())
    city_join = "LEFT JOIN user_properties AS city ON users.id = city.resource_id AND city.name = 'city'"
    assert_equal(city_join,
      User.user_properties_joins(:city))
    assert_equal(city_join,
      User.user_properties_joins('city'))
    city_street_join = "LEFT JOIN user_properties AS city ON users.id = city.resource_id AND city.name = 'city' LEFT JOIN user_properties AS street ON users.id = street.resource_id AND street.name = 'street'"
    assert_equal(city_street_join,
      User.user_properties_joins(:city, :street))
    # should allow passing arrays
    assert_equal(city_street_join,
      User.user_properties_joins([:city, :street]))
    # should ignore arguments which are not included in properties_list
    assert_equal(city_street_join,
      User.user_properties_joins(:city, :dont_belong_to_properties, :street))
  end

  # this test is an example for above test's functionality
  def test_should_allow_finding_by_properties
    result = User.find(:all, :joins => User.user_properties_joins(:city), :conditions => ['city.value = ?', @tim_city.value])
    assert_equal 1, result.size
    assert_equal @tim, result[0]
  end
end
