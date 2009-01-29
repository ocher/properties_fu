module Ocher
  module PropertiesFu
    def self.included(subject)
      subject.extend(ClassMethods)
    end

    module ClassMethods
      def properties_fu(properties_table, *properties)

        # define ActiveRecord class for properties_table. this class has defined attr_accessor called "is_changed"
        properties_table_class = Class.new(ActiveRecord::Base)
        properties_table_class.module_eval("attr_accessor :is_changed")
        properties_table_class_name = properties_table.to_s.singularize.camelize
        Object.const_set(properties_table_class_name, properties_table_class) unless Object.const_defined?(properties_table_class_name)
        # define has_many properties relation
        has_many properties_table, :foreign_key => 'resource_id', :dependent => :destroy

        module_eval <<-EOS
          # define properties_table_hash - {property.name => property}
          def #{properties_table}_hash
            if @#{properties_table}_hash.nil?
              @#{properties_table}_hash = {}
              #{properties_table}.each {|property| @#{properties_table}_hash[property.name] = property}
            end
            @#{properties_table}_hash
          end

          # define hook methods
          after_save :save_changed_#{properties_table}

          def save_changed_#{properties_table}
            #{properties_table}_hash.values.select {|p| p.is_changed == true}.each do |p|
              p.resource_id = id if p.new_record?
              p.save
            end
          end

          # define a method which returns list of properties - convert properties array to string representation - [:property1, :property2, ...]
          def self.#{properties_table}_list
            [#{properties.map{|p| ":#{p}"}.join(',')}]
          end
        EOS

        properties.each do |property|
          module_eval <<-EOS
            # define getters for properties
            def #{property}
              property = #{properties_table}_hash['#{property}']
              property.value unless property.nil?
            end

            # define setters for properties
            def #{property}=(value)
              property = #{properties_table}_hash['#{property}']
              # create a new property if it hasn't been defined already
              if property.nil?
                property = #{properties_table_class_name}.new(:name => '#{property}')
                #{properties_table}_hash['#{property}'] = property
              end
              property.value = value
              property.is_changed = true
            end
          EOS
        end
      end
    end
  end
end