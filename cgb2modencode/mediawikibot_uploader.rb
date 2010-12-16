# Adapted from:
# http://stanislavvitvitskiy.blogspot.com/2008/12/multipart-post-in-ruby.html
# Stanislav Vitvitskiy

require 'uri'
require 'net/http'
require 'net/https'

class MediawikiBot
  class Updater
    def initialize(url, edit_token, start_time, edit_time, cookie = nil)
      @user_cookie = cookie
      @edit_token = edit_token
      @start_time = start_time
      @edit_time = edit_time
      @url = url.is_a?(URI) ? url : URI.parse(url)
    end
    def post(content)
      boundary = '----RubyMultipartClient' + rand(1000000).to_s + 'ZZZZZ'
      parts = []
      parts << StringPart.new("--" + boundary + "\r\n")
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpSection\"\r\n\r\n#{""}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpStarttime\"\r\n\r\n#{@start_time}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpEdittime\"\r\n\r\n#{@edit_time}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpScrolltop\"\r\n\r\n#{0}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpSummary\"\r\n\r\nAutomatic update at #{Time.now}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpSave\"\r\n\r\nSave page")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpEditToken\"\r\n\r\n#{@edit_token}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpTextbox1\"\r\n\r\n#{content}")
      parts << StringPart.new( "\r\n--" + boundary + "--\r\n\r\n" )

      post_stream = MultipartStream.new( parts )
     
      req = Net::HTTP::Post.new(@url.request_uri, { "Cookie" => @user_cookie.cookie_string, "User-Agent" => "modENCODE Wiki Crawler" })
      req.content_length = post_stream.size
      req.content_type = 'multipart/form-data; boundary=' + boundary
      req.body_stream = post_stream
      http = Net::HTTP.new(@url.host, @url.port)
      http.use_ssl = true if @url.scheme == "https" 
      res = http.start { |http| http.request(req) }

      case res
      when Net::HTTPRedirection then
        # Follow redirection
        new_uri = URI.parse(res["Location"])
        if !new_uri.request_uri.include?("action=edit") then
          # Actually, this is just the post-upload redirect
          res
        else
          @url = new_uri
          handle.rewind
          post(name, handle)
        end
      when Net::HTTPSuccess then
        res
      else
        res.error!
      end
    end
  end
  class Uploader
    def initialize(url, cookie = nil)
      @user_cookie = cookie
      @url = url.is_a?(URI) ? url : URI.parse(url)
    end
    def post(name, handle)
      boundary = '----RubyMultipartClient' + rand(1000000).to_s + 'ZZZZZ'
     
      parts = []
      parts << StringPart.new("--" + boundary + "\r\n")
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpDestFile\"\r\n\r\n#{name}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpUploadDescription\"\r\n\r\nAutomatic upload at #{Time.now}")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpUpload\"\r\n\r\nUpload file")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpSourceType\"\r\n\r\nfile")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )
      parts << StringPart.new("Content-Disposition: form-data; name=\"wpIgnoreWarning\"\r\n\r\ntrue")
      parts << StringPart.new( "\r\n--" + boundary + "\r\n" )

      parts << StringPart.new(
        "Content-Disposition: form-data; name=\"" + "wpUploadFile" + "\"; filename=\"" + name + "\"\r\n" +
        "Content-Type: image/png\r\n\r\n"
      )
      parts << StreamPart.new(handle, handle.size)
      parts << StringPart.new( "\r\n--" + boundary + "--\r\n\r\n" )
     
      post_stream = MultipartStream.new( parts )
     
      req = Net::HTTP::Post.new(@url.request_uri, { "Cookie" => @user_cookie.cookie_string, "User-Agent" => "modENCODE Wiki Crawler" })
      req.content_length = post_stream.size
      req.content_type = 'multipart/form-data; boundary=' + boundary
      req.body_stream = post_stream
      http = Net::HTTP.new(@url.host, @url.port)
      http.use_ssl = true if @url.scheme == "https" 
      res = http.start { |http| http.request(req) }

      case res
      when Net::HTTPRedirection then
        # Follow redirection
        new_uri = URI.parse(res["Location"])
        if new_uri.request_uri.include?("File:") then
          # Actually, this is just the post-upload redirect
          new_uri.request_uri.match(/File:(.*)$/)[1]
        else
          @url = new_uri
          handle.rewind
          post(name, handle)
        end
      when Net::HTTPSuccess then
        name
      else
        res.error!
      end
    end
  end
  class StreamPart
    def initialize( stream, size )
      @stream, @size = stream, size
    end
    def size
      @size
    end
    def read ( offset, how_much )
      @stream.read( how_much )
    end
  end

  class StringPart
    def initialize ( str )
      @str = str
    end
    def size
      @str.length
    end
    def read ( offset, how_much )
      @str[offset, how_much]
    end
  end
  class MultipartStream
    def initialize( parts )
      @parts = parts
      @part_no = 0;
      @part_offset = 0;
    end
    def size
      total = 0
      @parts.each do |part|
        total += part.size
      end
      total
    end
    def read ( how_much )
     
      if @part_no >= @parts.size
        return nil;
      end
     
      how_much_current_part = @parts[@part_no].size - @part_offset
     
      how_much_current_part = if how_much_current_part > how_much
        how_much
      else
        how_much_current_part
      end
     
      how_much_next_part = how_much - how_much_current_part
     
      current_part = @parts[@part_no].read(@part_offset, how_much_current_part )

      if how_much_next_part > 0
        @part_no += 1
        @part_offset = 0
        next_part = read( how_much_next_part  )
        current_part + if next_part
          next_part
        else
          ''
        end
      else
        @part_offset += how_much_current_part
        current_part
      end
    end
  end
end
