module NoBrainer::Document::Index
  VALID_INDEX_OPTIONS = [:multi]
  extend ActiveSupport::Concern

  included do
    cattr_accessor :indexes, :instance_accessor => false
    self.indexes = {}
    self.index :id
  end

  module ClassMethods
    def index(name, *args)
      name = name.to_sym
      options = args.extract_options!
      options.assert_valid_keys(*VALID_INDEX_OPTIONS)

      raise "Too many arguments: #{args}" if args.size > 1

      kind, what = case args.first
        when nil   then [:single,   name.to_sym]
        when Array then [:compound, args.first.map(&:to_sym)]
        when Proc  then [:proc,     args.first]
        else raise "Index argument must be a lambda or a list of fields"
      end

      if name.in?(NoBrainer::Document::Attributes::RESERVED_FIELD_NAMES)
        raise "Cannot use a reserved field name: #{name}"
      end
      if has_field?(name) && kind != :single
        raise "Cannot reuse field name #{name}"
      end

      indexes[name] = {:kind => kind, :what => what, :options => options}
    end

    def remove_index(name)
      indexes.delete(name.to_sym)
    end

    def has_index?(name)
      !!indexes[name.to_sym]
    end

    def _field(attr, options={})
      if has_index?(attr) && indexes[attr][:kind] != :single
        raise "Cannot reuse index attr #{attr}"
      end

      super

      case options[:index]
      when nil    then
      when Hash   then index(attr, options[:index])
      when Symbol then index(attr, options[:index] => true)
      when true   then index(attr)
      when false  then remove_index(attr)
      end
    end

    def perform_create_index(index_name, options={})
      index_name = index_name.to_sym
      index_args = self.indexes[index_name]

      index_proc = case index_args[:kind]
        when :single   then nil
        when :compound then ->(doc) { index_args[:what].map { |field| doc[field] } }
        when :proc     then index_args[:what]
      end

      NoBrainer.run(self.rql_table.index_create(index_name, index_args[:options], &index_proc))
      wait_for_index(index_name) unless options[:wait] == false
      STDERR.puts "Created index #{self}.#{index_name}" if options[:verbose]
    end

    def perform_drop_index(index_name, options={})
      NoBrainer.run(self.rql_table.index_drop(index_name))
      STDERR.puts "Dropped index #{self}.#{index_name}" if options[:verbose]
    end

    def perform_update_indexes(options={})
      current_indexes = NoBrainer.run(self.rql_table.index_list).map(&:to_sym)
      wanted_indexes = self.indexes.keys - [:id] # XXX Primary key?

      (current_indexes - wanted_indexes).each do |index_name|
        perform_drop_index(index_name, options)
      end

      (wanted_indexes - current_indexes).each do |index_name|
        perform_create_index(index_name, options)
      end
    end
    alias_method :update_indexes, :perform_update_indexes

    def wait_for_index(index_name=nil, options={})
      args = [index_name].compact
      NoBrainer.run(self.rql_table.index_wait(*args))
    end
  end
end
