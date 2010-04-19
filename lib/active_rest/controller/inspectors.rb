#
# ActiveRest, a more powerful rest resources manager
# Copyright (C) 2008, Intercom s.r.l., windmillmedia
#
# = ActiveRest::Controller::Actions::Insepctors
#
# Author:: Lele Forzani <lele@windmill.it>, Alfredo Cerutti <acerutti@intercom.it>
# License:: Proprietary
#
# Revision:: $Id: inspectors.rb 5105 2009-08-05 12:30:05Z dot79 $
#
# == Description
#
#
#

module ActiveRest
module Controller
module Actions

  module Inspectors

    #
    # in your controller you can override schema action this way:
    #
    # def assocs
    #   super { |f|
    #     f.format_one { render ... }
    #     f.format_two { render ... }
    #   }
    # end
    #

    def schema(&blk)

      @schema = { :type => target_model.name,
                  :type_symbolized => target_model_to_underscore }

      target_model.columns.each { |x| @schema[x.name] = {
        :type => x.type,
        :primary => x.primary,
        :null => x.null,
        :default => x.default,
        :alternative_filter => target_model.attr_alternative_filter(x.name.to_sym) # this column must be sent for query filter?}
        }
      }

      if target_model.respond_to?(:ordered_attributes)
        if target_model.attribute_groups.has_key?(:virtual_attributes)

          target_model.ordered_attributes(:virtual_attributes).each do |v|
            type = target_model.attr_type(v)
            search = target_model.attr_search(v)
            @schema[v] = {
              :name => v,
              :type => (type.nil?) ? :string : type,
              :primary => false,
              :null => false,
              :default => '',
              :virtual => true,
              :search => (search.nil?) ? false : search
              }
          end
        end
      end

      target_model.reflections.each { |name, reflection|
        case reflection.macro
        when :composed_of
          @schema[name] = {
            :type => reflection.macro,
            :entries => []
          }
        else
          @schema[name] = {
            :type => reflection.macro,
            :embedded => !!(reflection.options[:embedded]),
            :entries => []
          }
        end
      }

      respond_to do |format|
        format.html { render :template => 'active_rest/schema' }
        format.xml { render :xml => @schema.to_xml, :status => :ok }
        format.json { render :json => @schema.to_json, :status => :ok }
        format.jsone { render :json => @schema.to_json, :status => :ok }
        format.yaml { render :yaml => @schema.to_yaml, :status => :ok }
        blk.call(format) if blk
      end
    end
  end

end
end
end
