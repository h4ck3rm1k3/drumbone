#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'environment'


get /^\/(legislator|bill|roll)\.(json)$/ do
  model = params[:captures][0].camelize.constantize
  fields = fields_for model, params[:sections]
  
  unless document = model.first(
      :conditions => conditions_for(model.unique_keys, params), 
      :fields => fields)
    raise Sinatra::NotFound, "#{model} not found"
  end
  
  json model, attributes_for(document, fields), params[:callback]
end

get /^\/(bills)\.(json)$/ do
  fields = fields_for Bill, params[:sections]
  
  bills = Bill.all({
    :conditions => conditions_for(Bill.search_keys, params).
      merge(:session => (params[:session] || Bill.current_session.to_s)), 
    :fields => fields,
    :order => "#{params[:order] || 'introduced_at'} DESC"
  }.merge(pagination_for(params)))
  
  json Bill, bills.map {|bill| attributes_for bill, fields}, params[:callback]
end

get /^\/(rolls)\.(json)$/ do
  fields = fields_for Roll, params[:sections]
  
  rolls = Roll.all({
    :conditions => conditions_for(Roll.search_keys, params),
    :fields => fields,
    :order => "#{params[:order] || 'voted_at'} DESC"
  }.merge(pagination_for(params)))
  
  json Roll, rolls.map {|roll| attributes_for roll, fields}, params[:callback]
end


def json(model, object, callback = nil)
  response['Content-Type'] = 'application/json'
  
  key = model.to_s.underscore
  key = key.pluralize if object.is_a?(Array)
  
  json = {
    key => object,
    :sections => model.fields.keys.sort_by {|x, y| x == :basic ? -1 : x.to_s <=> y.to_s}
  }.to_json
  
  callback ? "#{callback}(#{json});" : json
end


def conditions_for(keys, params)
  conditions = {}
  keys.each do |key|
    conditions = conditions.merge(key => params[key]) if params[key]
  end
  conditions
end

def pagination_for(params)
  {
    :limit => (params[:per_page] || 20).to_i,
    :offset => ((params[:page] || 1).to_i - 1 ) * (params[:per_page] || 20).to_i
  }
end

def fields_for(model, sections)
  keys = sections ? (sections || '').split(',') : model.fields.keys
  keys.uniq.map {|section| model.fields[section.to_sym]}.flatten.compact
end

def attributes_for(document, fields)
  attributes = document.attributes
  attributes.keys.each {|key| attributes.delete(key) unless fields.include?(key.to_sym)}
  attributes
end