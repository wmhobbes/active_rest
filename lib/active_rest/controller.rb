#
# ActiveRest, a more powerful rest resources manager
# Copyright (C) 2008, Intercom s.r.l., windmillmedia
#
# = ActiveRest::Controller::Core
#
# Author:: Lele Forzani <lele@windmill.it>, Alfredo Cerutti <acerutti@intercom.it>,
#          Angelo Grossini <angelo@intercom.it>
#
# License:: Proprietary
#
# Revision:: $Id: core.rb 5105 2009-08-05 12:30:05Z dot79 $
#
# == Description
#
#
#

require 'ostruct'

module ActiveRest
module Controller

  include Finder
  include Pagination # manage pagination
  include Rest # default verbs and actions
  include MembersRest # default verbs and actions
  include Inspectors # extra default actions
  include Validations # contains validation actions

  @config = OpenStruct.new(
    :cache_path => File.join(Rails.root, 'tmp', 'cache', 'active_rest'),
    :x_sendfile => false,
    :save_pagination => true,
    :default_page_size => true,
    :members_crud => false,
    :route_expand_model_namespace => false
  )

  class << self
    attr_reader :config
  end

  class MethodNotAllowed < StandardError; end
  class BadRequest < StandardError; end
  class NotFound < StandardError; end
  class NotAcceptable < StandardError; end

  def self.included(base)
    base.class_eval do
      class_inheritable_accessor :model
      class_inheritable_accessor :options
      class_inheritable_accessor :xact_handler
      class_inheritable_accessor :attrs

      attr_accessor :target, :targets

      self.xact_handler = :rest_default_transaction_handler

#      build_associations_proxies

      # if read only not allow these actions
      prepend_before_filter :check_validation_action, :only => [ :update, :create ] # are we just requiring validations ?
      prepend_before_filter :check_read_only

      # if we get here, chek for polymorphic associations
      before_filter :prepare_polymorphic_association, :only => :create

      before_filter :prepare_i18n
      before_filter :find_target, :only => [ :show, :edit, :update, :destroy, :validate_update ] # 1 resource?
      before_filter :find_targets, :only => [ :index ] # find all resources ?

      base.append_after_filter :x_sendfile, :only => [ :index ]

      rescue_from Controller::Finder::Expression::SyntaxError, :with => lambda { generic_rescue_action(:bad_request) }
      rescue_from NotFound, :with => lambda { generic_rescue_action(:not_found) }
      rescue_from ActiveRecord::RecordNotFound, :with => lambda { generic_rescue_action(:not_found) }
      rescue_from MethodNotAllowed, :with => lambda { generic_rescue_action(:method_not_allowed) }
      rescue_from BadRequest, :with => lambda { generic_rescue_action(:bad_request) }
      rescue_from NotAcceptable, :with => lambda { generic_rescue_action(:not_acceptable) }
    end

    base.extend(ClassMethods)
  end

  def rest_default_transaction_handler
    model.transaction do
      yield
    end
  end

  class Attribute < Hel::PublicModel::Attribute
    attr_accessor :sub_attributes

    def initialize(*args)
      super(*args)
      @sub_attributes = {}
    end

    def virtual(type, &block)

      raise 'Double defined attribute' if @type

      @type = type
      @source = block
      @readable = true
      @writable = false
      @creatable = false
    end

    def attribute(name, &block)
      # TODO Check that attribute is embedded/nested

      @sub_attributes[name] ||= Attribute.new(name)
      @sub_attributes[name].instance_eval(&block)
      @sub_attributes[name]
    end
  end

  module ClassMethods

    def rest_transaction_handler(method)
      self.xact_handler = method
    end

    def rest_controller_for(model, options = {})
      self.model = model
      self.options = options
      self.attrs = {}
    end

    def rest_controller(options = {})
      rest_controller_for(self.controller_name.classify.constantize, options)
    end

    def attribute(name, &block)
      self.attrs[name] ||= Attribute.new(name)
      self.attrs[name].instance_eval(&block)
      self.attrs[name]
    end

    private

    def map_column_type(type)
      case type
      when :datetime
        :timestamp
      else
        type
      end
    end
  end

  #
  # in your controller you can override these methods this way:
  #
  # def verify_authenticity_token
  #   super { |f|
  #     f.format_one { render ... }
  #     f.format_two { render ... }
  #   }
  # end
  #

  protected

  #
  # handle authenticity token (html in primis)
  #
#  def verify_authenticity_token(&blk)
#    respond_to do | format |
#      format.html { super }
#      format.xml {}
#      format.json {}
#      format.jsone {}
#      format.yaml {}
#      blk.call(format) if blk # overriding to handle other format
#      format.any { super } # unhandled format? do authenticity token!
#    end
#  end

  #
  # setup I18n if options has this information
  #
  def prepare_i18n
    I18n.locale = params[:language].to_sym if params[:language]
  end

  private

  TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE', 'y', 'yes', 'Y', 'YES', :true, :t].to_set
  def is_true?(val)
    TRUE_VALUES.include?(val)
  end

  #
  # generic rescue action. when html will handle a block
  #
  def generic_rescue_action(status)
    respond_to do |format|
      yield format if block_given? # when overriding to handle other format
      format.any { head :status => status, :nothing => true } # any other format
    end
  end

  #
  # model name to underscore, even when namespaced
  #
  def model_symbol
    model.to_s.underscore.gsub(/\//, '_')
  end

  #
  # find a single resource; return object or, if action is not include
  # into a object ruleset, return an hash
  #
  def find_target(options={})
    joins, select = build_joins

    tid = options[:id] || params[:id]
    options.delete(:id)

    find_options = {}
    find_options[:select] = select unless select.blank?
    find_options[:joins] = joins unless joins.blank?
    @target = model.find(tid, find_options)
  end

  #
  # find all with conditions
  #
  def find_targets

    # Update our pagination state from params[] and session if persistant
    update_pagination_state

    # 1^ prepare basic conditions

    finder_rel = build_finder_relation
    pagination_rel = build_pagination_relation

#      # 2^ build joins - some finder may change :select and :joins argument or can clash with them
#      joins, select = build_joins
#      opts[:select] = select unless select.nil?||select.empty?
#      opts[:joins] = joins unless joins.nil?||joins.empty?
#
#      preprocessor = index_options[:preprocess]
#      if preprocessor && (preprocessor.is_a?(String) || preprocessor.instance_of?(Module))
#        preprocessor = preprocessor.constantize if preprocessor.is_a?(String)
#        preprocessor = preprocessor.to_s.constantize if preprocessor.is_a?(Symbol)
#        opts = preprocessor::preprocess(opts, :params => params)
#      end

#      # 3^ detect has_many through associations (in that case try to use the right finder)
#      hmt_habtm_finder = ActiveRest::Helpers::Routes::Mapper.has_many_through_or_habtm?(model, params)

#      if hmt_habtm_finder
######FIXME
#        resources = eval(hmt_habtm_finder+'.find(:all, pagination_and_conditions.dup)') #attention! .dup to avoid :readonly => true ??
#      else
        @targets = (finder_rel & pagination_rel).all
        @count = finder_rel.count
#      end
  end

  #
  # loop parameters trying to guess polymorphic fields to setup
  #
  def prepare_polymorphic_association
    params.each do |p|
      if p[0].match(/.*_id$/)
        lookup_for_polymorphic_association(p) { |param_id|
          params[model_symbol][ActiveRest::Helpers::Routes::Mapper::POLYMORPHIC[model.to_s][:foreign_type]] = ActiveRest::Helpers::Routes::Mapper::AS[param_id][:map_to_model]
          params[model_symbol][ActiveRest::Helpers::Routes::Mapper::AS[param_id][:map_to_primary_key]] = p[1]
        }
      end
    end
  end

  #
  # avoid any action that can modify the record or change the table
  #
  def check_read_only
    raise MethodNotAllowed if options[:read_only] && request.method != 'GET'
  end


  #
  # parse join if controller declared the option :join => ...
  #
  # there are these cases:
  #
  # 1) :join => { :genus => [:name] }
  # this tell to join the class genus and return only the field name
  #
  # 2) :join => { :assoc => true }
  # associa tutti i campi, rimappa i nomi come #{table_name}_#{column_name}
  #
  # 3) :join => { :assoc => [:colonna1, :colonna2....] }
  # associa i campi specificati, rimappa i nomi come #{table_name}_#{column_name}
  #
  # 4) :join => { :assoc => { :colonna1 => 'nome1', :colonna2 => 'nome2',.... } }
  # associa i campi specificati, usa i nomi specificati
  #
  def parse_joins
    join_options = options.has_key?(:join) ? options[:join] : {}

    # any unknown reflection will be ignored
    joins = join_options.keys.select do | j |
      join_options[j] && model.reflections.has_key?(j.to_sym)
    end if join_options

    parsed = {}

    joins.each do | reflection_key |
      fields = []
      join = join_options[reflection_key].is_a?(Symbol) || join_options[reflection_key].is_a?(String) ? [join_options[reflection_key]] : join_options[reflection_key]

      table_name = model.reflections[reflection_key].class_name.constantize.table_name
      quoted_table_name = model.connection.quote_table_name(table_name)

      #puts "JOIN OPTIONS  --> #{join.inspect}"
      if join.is_a?(Array)
        #
        # { :users => [:name] }
        #
        join.each do | f |
            parsed["#{quoted_table_name}.#{model.connection.quote_column_name(f.to_s)}"] = model.connection.quote_column_name("#{reflection_key.to_s}_#{f.to_s}")
        end
      elsif join.is_a?(Hash) && !join.empty?
        #
        # { :users => { :name => 'user_name' } } # this permit field name rewriting
        #
        join.each do | f, f1 |
            parsed["#{quoted_table_name}.#{model.connection.quote_column_name(f.to_s)}"] = model.connection.quote_column_name(f1.to_s)
        end
      else
        #
        # { :crap => true, :contacts => true }  # ex. crap does not exist and has been ignored
        # { :users => [:name], :contacts => true } # array
        # { :users => :name, :contacts => true } # string
        #
        model.reflections[reflection_key].klass.column_names.each do | f |
            parsed["#{quoted_table_name}.#{model.connection.quote_column_name(f.to_s)}"] = model.connection.quote_column_name("#{reflection_key.to_s}_#{f.to_s}")
        end
      end
    end

    return [joins, parsed]
  end

  def build_joins
    joins, select = parse_joins

    select = select.collect do | a, b |
      "#{a} AS #{b}"
    end

    select = "#{model.quoted_table_name}.*, #{ select.join(', ') }" unless select.nil? || select.empty?

    return [joins,select]
  end
end

end
