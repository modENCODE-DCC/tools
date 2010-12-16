class CookieJar < Hash
  def update(cookietxt)
    cookietxt.split(/, /).each { |cookie|
      (k, v) = cookie.split(/; /)[0].split(/=/)
      self[k] = v
    }
  end
  def cookie_string
    self.map { |k, v| "#{k}=#{v}" }.join("; ")
  end
end
