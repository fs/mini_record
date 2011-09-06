module MiniRecord
  module AutoSchema
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def table_definition
        @_table_definition ||= begin
          tb = ActiveRecord::ConnectionAdapters::TableDefinition.new(connection)
          tb.primary_key(primary_key)
        end
      end
      alias :col :table_definition
      alias :key :table_definition
      alias :property :table_definition

      def reset_table_definition!
        @_table_definition = nil
      end

      def schema
        reset_table_definition!
        yield table_definition
      end
      alias :keys :schema
      alias :properties :schema

      def auto_upgrade!
        # Table doesn't exist, create it
        unless connection.tables.include?(table_name)
          # TODO: Add to create_table options
          class << connection; attr_accessor :table_definition; end unless connection.respond_to?(:table_definition=)
          connection.table_definition = table_definition
          connection.create_table(table_name)
          connection.table_definition = ActiveRecord::ConnectionAdapters::TableDefinition.new(connection)
        end

        # Grab database columns
        fields_in_db = connection.columns(table_name).inject({}) do |hash, column|
          hash[column.name] = column
          hash
        end

        # Grab new schema
        fields_in_schema = table_definition.columns.inject({}) do |hash, column|
          hash[column.name.to_s] = column
          hash
        end

        # Remove fields from db no longer in schema
        (fields_in_db.keys - fields_in_schema.keys & fields_in_db.keys).each do |field|
          column = fields_in_db[field]
          connection.remove_column table_name, column.name
        end

        # Add fields to db new to schema
        (fields_in_schema.keys - fields_in_db.keys).each do |field|
          column  = fields_in_schema[field]
          options = {:limit => column.limit, :precision => column.precision, :scale => column.scale}
          options[:default] = column.default if !column.default.nil?
          options[:null]    = column.null    if !column.null.nil?
          connection.add_column table_name, column.name, column.type.to_sym, options
        end

        # Change attributes of existent columns
        (fields_in_schema.keys & fields_in_db.keys).each do |field|
          if field != primary_key #ActiveRecord::Base.get_primary_key(table_name)
            changed  = false  # flag
            new_type = fields_in_schema[field].type.to_sym
            new_attr = {}

            # First, check if the field type changed
            if fields_in_schema[field].type.to_sym != fields_in_db[field].type.to_sym
              changed = true
            end

            # Special catch for precision/scale, since *both* must be specified together
            # Always include them in the attr struct, but they'll only get applied if changed = true
            new_attr[:precision] = fields_in_schema[field][:precision]
            new_attr[:scale]     = fields_in_schema[field][:scale]

            # Next, iterate through our extended attributes, looking for any differences
            # This catches stuff like :null, :precision, etc
            fields_in_schema[field].each_pair do |att,value|
              next if att == :type or att == :base or att == :name # special cases
              if !value.nil? && value != fields_in_db[field].send(att)
                new_attr[att] = value
                changed = true
              end
            end

            # Change the column if applicable
            connection.change_column table_name, field, new_type, new_attr if changed
          end
        end

        # Reload column information
        reset_column_information
      end
    end # ClassMethods
  end # AutoSchema
end # MiniRecord
