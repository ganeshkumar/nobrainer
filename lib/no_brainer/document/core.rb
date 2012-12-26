module NoBrainer::Document::Core
  extend ActiveSupport::Concern

  # TODO This assume the primary key is id.
  # RethinkDB can have a custom primary key. careful.
  include ActiveModel::Conversion

  included do
    # TODO test these includes
    extend ActiveModel::Naming
    extend ActiveModel::Translation
  end

  def initialize(attrs={}, options={})
    clear_internal_cache
  end

  def clear_internal_cache
  end

  def ==(other)
    return super unless self.class == other.class
    !id.nil? && id == other.id
  end
  alias_method :eql?, :==

  delegate :hash, :to => :id

  def table
    self.class.table
  end

  def table_name
    self.class.table_name
  end

  module ClassMethods
    def table_name
      # TODO FIXME Inheritance can make things funny here. Pick the parent.
      self.name.underscore.gsub('/', '__')
    end

    # Even though we are using class variables,
    # these guys are thread-safe.
    # It's still racy, but the race is harmless.
    def table
      @table ||= RethinkDB::RQL.table(table_name)
    end

    def ensure_table!
      self.count unless @table_created
      @table_created = true
    end
  end
end
