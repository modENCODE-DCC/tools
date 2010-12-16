require 'uri'
require 'cgi'
require 'net/http'
require 'net/https'
require 'cookie_jar'
require 'mediawikibot_uploader'

class MediawikiBot
  LOGIN_PAGE = "Special:UserLogin"
  UPLOAD_PAGE = "Special:Upload"
  class PageNotFoundException < Exception
  end

  # http://user:password@host.com/wikipage
  def initialize(uri, username = nil, password = nil)
    @conn_info = URI.parse(uri)
    @conn_info = URI.parse("http://#{uri}") if @conn_info.host.nil?
    @conn_info.user = username unless username.nil?
    @conn_info.password = password unless password.nil?
    @user_cookie = CookieJar.new

    login()
  end
  def logged_in?
    return !@user_cookie["modencode_wikiUserID"].nil?
  end
  def get_page_text(title)
    r = get_page(title)
    m = r.body.match(/<textarea[^>]*wpTextbox1[^>]*>([^<]*)<\/textarea/m)
    raise PageNotFoundException.new("No textarea found on edit page for: #{title}") unless m
    raise PageNotFoundException.new("Page does not exist: #{title}") if r.body.match(/"mw-newarticletext"/)
    content = CGI::unescapeHTML(m[1])
  end

  def get_page(title)
    page_uri = @conn_info.clone
    page_uri.query = "title=#{URI.escape(title)}&action=edit"
    get_page_by_uri(page_uri)
  end
  def upload_image(img_name, handle)
    raise ArgumentError.new("Not logged in!") unless logged_in?

    url = @conn_info.clone
    url.user = url.password = nil
    url.query = "title=#{URI.escape(UPLOAD_PAGE)}"
    u = Uploader.new(url, @user_cookie)
    u.post(img_name, handle)
  end
  def update_page(title, new_content)
    raise ArgumentError.new("Not logged in!") unless logged_in?

    page_uri = @conn_info.clone
    page_uri.user = page_uri.password = nil
    page_uri.query = "title=#{URI.escape(title)}&action=edit"

    r = get_page_by_uri(page_uri)

    edit_token = find_input_value_in_content(r.body, "wpEditToken")
    start_time = find_input_value_in_content(r.body, "wpStarttime")
    edit_time = find_input_value_in_content(r.body, "wpEdittime")

    page_uri.query = "title=#{URI.escape(title)}&action=submit"
    u = Updater.new(page_uri, edit_token, start_time, edit_time, @user_cookie)
    res = u.post(new_content)

    raise RuntimeError.new("Failed to update page #{title}") if res.body.include?("previewnote")
    res
  end
  def post_form(title, form_data)
    raise ArgumentError.new("Not logged in!") unless logged_in?

    page_uri = @conn_info.clone
    page_uri.user = page_uri.password = nil
    page_uri.query = "title=#{URI.escape(title)}&action=purge"

    post_form_to_uri(page_uri, form_data)
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
  def find_input_value_in_content(body, name)
    m = body.match(/<[^>]*name="#{Regexp.escape(name)}"[^>]*>/)
    m = m[0].match(/value="([^"]*)"/) unless m.nil?
    raise RuntimeError.new("Couldn't get #{name} input field value") if m.nil?
    m[1]
  end
  def login(uri = nil, allowed_redirs = 5)
    raise ArgumentError.new("HTTP redirection to deep on login") if allowed_redirs == 0

    login_uri = (uri || @conn_info).clone
    user = login_uri.user || @conn_info.user
    password = login_uri.password || @conn_info.password
    login_uri.user = login_uri.password = nil
    login_uri.query = "title=#{URI.escape(LOGIN_PAGE)}&action=submitlogin&type=login"

    req = Net::HTTP::Post.new(login_uri.request_uri, { "Cookie" => @user_cookie.cookie_string, "User-Agent" => "modENCODE Wiki Crawler" })
    req.set_form_data({
      'wpName' => user,
      'wpPassword' => password,
      'wpLoginattempt' => 'Log in',
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
      res
    else
      res.error!
    end
  end
  def post_form_to_uri(page_uri, form_data, allowed_redirs = 5)
    raise ArgumentError.new("HTTP redirection to deep on form post") if allowed_redirs == 0

    req = Net::HTTP::Post.new(page_uri.request_uri, { "Cookie" => @user_cookie.cookie_string, "User-Agent" => "modENCODE Wiki Crawler" })
    req.set_form_data(form_data)

    http = Net::HTTP.new(page_uri.host, page_uri.port)
    http.use_ssl = true if page_uri.scheme == "https"
    res = http.start { |http| http.request(req) }

    case res
    when Net::HTTPRedirection then
      # Follow redirection
      new_uri = URI.parse(res["Location"])
      if new_uri.query.include?("action=purge") then
        res
      else
        post_form_to_uri(new_uri, form_data, allowed_redirs-1)
      end
    when Net::HTTPSuccess then
      res
    else
      res.error!
    end
  end
end

