require 'uri'
require 'cgi'
require 'net/http'
require 'net/https'
require 'cookie_jar'
require 'soap/wsdlDriver'

class DbfieldsBot
  class NoFormDataException < Exception
  end
  def initialize(wsdl_url)
    wsdl_uri = URI.parse(wsdl_url)
    user = wsdl_uri.user
    password = wsdl_uri.password
    wsdl_uri.user = wsdl_uri.password = nil
    @client = SOAP::WSDLDriverFactory.new(wsdl_uri.to_s).create_rpc_driver
    @user_cookie = @client.getLoginCookie(user, password, false)
  end

  def logged_in?
    @user_cookie && @user_cookie.lguserid && @user_cookie.lguserid != ""
  end
  def get_data(title, version = nil)
    raise ArgumentError.new("Not logged in!") unless logged_in?
    d = @client.getFormData(:name => title, :version => version, :auth => @user_cookie)
    raise NoFormDataException.new("No form data returned") if d.nil?
    d.string_values.inject(Hash.new) { |h, v| h[v.name] = v.values.first; h }
  end
  def update(mediawiki_bot, title, form_data)
    raise ArgumentError.new("Must be given a logged-in MediawikiBot") unless mediawiki_bot.logged_in?

    form_data = form_data.inject(Hash.new) { |h, kv| h["modENCODE_dbfields[#{kv[0]}]"] = kv[1]; h }
    mediawiki_bot.post_form(title, form_data)
  end 
end
