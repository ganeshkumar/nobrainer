module NoBrainer::Document::Types
  extend ActiveSupport::Concern

  module CastUserToDB
    extend self
    InvalidType = NoBrainer::Error::InvalidType

    def String(value)
      case value
      when Symbol then value.to_s
      else raise InvalidType
      end
    end

    def Integer(value)
      case value
      when String
        value = value.strip.gsub(/^\+/, '')
        value.to_i.tap { |new_value| new_value.to_s == value or raise InvalidType }
      when Float
        value.to_i.tap { |new_value| new_value.to_f == value or raise InvalidType }
      else raise InvalidType
      end
    end

    def Float(value)
      case value
      when Integer then value.to_f
      when String
        value = value.strip.gsub(/^\+/, '')
        value = value.gsub(/0+$/, '') if value['.']
        value = value.gsub(/\.$/, '')
        value = "#{value}.0" unless value['.']
        value.to_f.tap { |new_value| new_value.to_s == value or raise InvalidType }
      else raise InvalidType
      end
    end

    def Boolean(value)
      case value
      when TrueClass  then true
      when FalseClass then false
      when String, Integer
        value = value.to_s.strip.downcase
        return true  if value.in? %w(true yes t 1)
        return false if value.in? %w(false no f 0)
        raise InvalidType
      else raise InvalidType
      end
    end

    def Symbol(value)
      case value
      when String
        value = value.strip
        raise InvalidType if value.empty?
        value.to_sym
      else raise InvalidType
      end
    end

    def lookup(type)
      public_method(type.to_s)
    rescue NameError
      proc { raise InvalidType }
    end
  end

  module CastDBToUser
    extend self

    def Symbol(value)
      value.to_sym rescue value
    end

    def lookup(type)
      public_method(type.to_s)
    rescue NameError
      nil
    end
  end

  included do
    # We namespace our fake Boolean class to avoid polluting the global namespace
    class_exec do
      class Boolean
        def initialize; raise; end
        def self.inspect; 'Boolean'; end
        def self.to_s; inspect; end
        def self.name; inspect; end
      end
    end
    before_validation :add_type_errors

    # Fast access for db->user cast methods for performance when reading from
    # the database.
    singleton_class.send(:attr_accessor, :cast_db_to_user_fields)
    self.cast_db_to_user_fields = Set.new
  end

  def add_type_errors
    return unless @pending_type_errors
    @pending_type_errors.each do |name, error|
      errors.add(name, :invalid_type, :type => error.human_type_name)
    end
  end

  def assign_attributes(attrs, options={})
    super
    if options[:from_db]
      self.class.cast_db_to_user_fields.each do |attr|
        field_def = self.class.fields[attr]
        type = field_def[:type]
        value = @_attributes[attr.to_s]
        unless value.nil? || value.is_a?(type)
          @_attributes[attr.to_s] = field_def[:cast_db_to_user].call(value)
        end
      end
    end
  end

  module ClassMethods
    def cast_user_to_db_for(attr, value)
      field_def = fields[attr.to_sym]
      return value if !field_def
      type = field_def[:type]
      return value if value.nil? || type.nil? || value.is_a?(type)
      field_def[:cast_user_to_db].call(value)
    rescue NoBrainer::Error::InvalidType => error
      error.type = field_def[:type]
      error.value = value
      error.attr_name = attr
      raise error
    end

    def inherited(subclass)
      super
      subclass.cast_db_to_user_fields = self.cast_db_to_user_fields.dup
    end

    def _field(attr, options={})
      super

      if options[:cast_db_to_user]
        ([self] + descendants).each do |klass|
          klass.cast_db_to_user_fields << attr
        end
      end

      inject_in_layer :types do
        define_method("#{attr}=") do |value|
          begin
            value = self.class.cast_user_to_db_for(attr, value)
            @pending_type_errors.try(:delete, attr)
          rescue NoBrainer::Error::InvalidType => error
            @pending_type_errors ||= {}
            @pending_type_errors[attr] = error
          end
          super(value)
        end

        define_method("#{attr}?") { !!read_attribute(attr) } if options[:type] == Boolean
      end
    end

    def field(attr, options={})
      if options[:type]
        options = options.merge(
          :cast_user_to_db => NoBrainer::Document::Types::CastUserToDB.lookup(options[:type]),
          :cast_db_to_user => NoBrainer::Document::Types::CastDBToUser.lookup(options[:type]))
      end
      super
    end
  end
end
