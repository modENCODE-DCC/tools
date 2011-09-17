require 'uri'
require 'cgi'
require 'net/http'
require 'net/https'
require 'cookie_jar'

class AtlassianwikiBot
  LOGIN_PAGE = "/login.action"
  LOGOUT_PAGE = "/logout.action"
  def initialize(uri, username = nil, password = nil)
    @conn_info = URI.parse(uri)
    @conn_info = URI.parse("http://#{uri}") if @conn_info.host.nil?
    @conn_info.user = username unless username.nil?
    @conn_info.password = password unless password.nil?
    @user_cookie = CookieJar.new
#    puts "cookie before login: #{@user_cookie["crowd.token_key"]}"
    login()
    puts "cookie after login: #{@user_cookie["crowd.token_key"]}"
  end

  def logged_in?
#   puts "cookie during login-check: #{@user_cookie.inspect()}"
   status = (@user_cookie["crowd.token_key"] && (@user_cookie["crowd.token_key"] != "") && (@user_cookie["crowd.token_key"] != "\"\""))
#   puts "logged in status: #{status}"
   return status
  end

  def logout(uri, allowed_redirs = 5)
    raise ArgumentError.new("HTTP redirection to deep on login") if allowed_redirs == 0
    logout_uri = (URI.parse(uri).merge(LOGOUT_PAGE)).clone
#    puts "logging out at #{logout_uri.path}"
    logout_uri.user = @conn_info.user unless @conn_info.nil?
    logout_uri.password = @conn_info.password unless @conn_info.nil?
    logout_uri.user = logout_uri.password = nil

    req = Net::HTTP::Post.new(logout_uri.path)
    http = Net::HTTP.new(logout_uri.host, logout_uri.port)
    http.use_ssl = true if logout_uri.scheme == "https"
    res = http.start { |http| http.request(req) }
    case res
    when Net::HTTPRedirection, Net::HTTPSuccess then
      # OK
      puts "logout OK"
      @user_cookie["crowd.token_key"] = "";      
      #@user_cookie.update(res["Set-Cookie"]) if res["Set-Cookie"]
#      puts "checking status after logout #{logged_in?()}"
      res
    else
      res.error!
    end
  end


  def get_page_text(title)
    r = get_page(title)
    m = r.body.match(/id="editPageLink"[^>]*href="([^"]*)"/)
    raise RuntimeError.new("Couldn't find edit page link for #{title}") unless m
    r = get_page(m[1])
    m = r.body.match(/<textarea[^>]*name="content"[^>]*>([^<]*)</m) 
    raise RuntimeError.new("Couldn't find content on edit page for #{title}") unless m
    content = CGI::unescapeHTML(m[1])
  end

  def get_page_text_for_content(body)
    m = body.match(/id="editPageLink"[^>]*href="([^"]*)"/)
    raise RuntimeError.new("Couldn't find edit page link in body") unless m
    r = get_page(m[1])
    m = r.body.match(/<textarea[^>]*name="content"[^>]*>([^<]*)</m) 
    raise RuntimeError.new("Couldn't find content on edit page in body") unless m
    content = CGI::unescapeHTML(m[1])
  end

  def get_page(title)
    page_uri = @conn_info.clone.merge(title)
    get_page_by_uri(page_uri)
  end

  private
  def get_page_by_uri(page_uri, allowed_redirs = 5)
    raise ArgumentError.new("Not logged in!") unless logged_in?

    req = Net::HTTP::Get.new(page_uri.request_uri, { "Cookie" => @user_cookie.cookie_string, "User-Agent" => "modENCODE Wiki Crawler" })

    http = Net::HTTP.new(page_uri.host, page_uri.port)
    http.use_ssl = true if page_uri.scheme == "https"
    res = http.start { |http| http.request(req) }

    case res
    when Net::HTTPRedirection then
      # Follow redirection
      new_uri = URI.parse(res["Location"])
      new_uri.user = page_uri.user
      new_uri.password = page_uri.password
      get_page_by_uri(new_uri, allowed_redirs-1)
    when Net::HTTPSuccess then
      res
    else
      res.error!
    end
  end

  def login(uri = nil, allowed_redirs = 5)
    raise ArgumentError.new("HTTP redirection to deep on login") if allowed_redirs == 0
    login_uri = (uri || @conn_info.merge(LOGIN_PAGE)).clone
    user = login_uri.user || @conn_info.user
    password = login_uri.password || @conn_info.password
    login_uri.user = login_uri.password = nil

    req = Net::HTTP::Post.new(login_uri.request_uri, { "Cookie" => @user_cookie.cookie_string, "User-Agent" => "modENCODE Wiki Crawler" })
    req.set_form_data({
      'os_username' => user,
      'os_password' => password,
      'login' => "Log In",
      'os_destination' => ""
    })

    http = Net::HTTP.new(login_uri.host, login_uri.port)
    http.use_ssl = true if login_uri.scheme == "https"
    res = http.start { |http| http.request(req) }

    case res
    when Net::HTTPRedirection then
      # Follow redirection
      @user_cookie.update(res["Set-Cookie"]) if res["Set-Cookie"]
      unless logged_in? then
        new_uri = URI.parse(res["Location"])
        new_uri.user = login_uri.user
        new_uri.password = login_uri.password
        login(new_uri, allowed_redirs-1)
      end
      res
    when Net::HTTPSuccess then
      @user_cookie.update(res["Set-Cookie"]) if res["Set-Cookie"]
      puts "logged in to CGB-Wiki"
      res
    else
      res.error!
    end
  end
end
