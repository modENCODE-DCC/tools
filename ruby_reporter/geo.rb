#!/usr/bin/ruby

require 'net/http'
require 'rexml/document'
require 'pp'

class Eutils
  attr_accessor :endpoint, :service

  def efetch(ids = nil, webenv = nil, query_key = 0, db = "gds", report = "asn.1", mode = "xml")
    query = { :db => db, :format => "xml", :report => report, :mode => mode }
    if ids then
      query["id"] = ids.join(",") if ids.is_a?(Enumerable)
      query["id"] = ids if (ids && !ids.is_a?(Enumerable))
    elsif webenv then
      query["WebEnv"] = webenv if webenv
      query["query_key"] = query_key
    end
    response = request("efetch.fcgi", query)
    return response
  end

  def esummary(ids = nil, webenv = nil, query_key = 0, db = "gds")
    query = { :db => db }
    if ids then
      query["id"] = ids.join(",") if ids.is_a?(Enumerable)
      query["id"] = ids if (ids && !ids.is_a?(Enumerable))
    elsif webenv then
      query["WebEnv"] = webenv if webenv
      query["query_key"] = query_key
    end
    response = request("esummary.fcgi", query)
    r = REXML::Document.new(response)
    return r
  end

  def esearch(title, db = "gds")

    res = request("esearch.fcgi", {
      :db => db,
      :term => title
    })

    r = REXML::Document.new(res)
    if r.nil? then
      return nil
    else
      return [
        r.elements["eSearchResult"].elements["WebEnv"].text,
        r.elements["eSearchResult"].elements["QueryKey"].text,
        r.elements["eSearchResult"].elements["IdList"].elements.map { |elem_id| elem_id.text }
      ]
    end
  end

  def request(resource, args = nil)
    url = URI.join("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/", resource)
    args = Hash.new unless args
    args["tool"] = "modENCODE Pipeline"
    args["email"] = "yostinso@berkelybop.org"
    args["usehistory"] = "y"
    url.query = args.map { |k, v| "#{URI.encode(k.to_s)}=#{URI.encode(v)}" }.join("&") if args
    req = Net::HTTP::Get.new(url.request_uri)

    http = Net::HTTP.new(url.host, url.port)
    response = http.start() { |conn| conn.request(req) }
    return response.body
  end

end

