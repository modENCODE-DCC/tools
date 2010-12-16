class ModencodeTemplate
  class BadPageContentException < ArgumentError
  end
  # __NOTOC__
  # {{Template:Reagent:CelnikerSample}}
  # ==More information==
  # <!--
  #     .... captured metadata ....
  # -->
  # ===Referenced Protocols===
  # .....
  # ===Notes===
  # .....
  # ===QC Data===
  # .....
  # ===Comments===
  # .....
  TEMPLATE="__NOTOC__\n" +
    "{{Template:Reagent:CelnikerSample}}\n" +
    "==More information==\n" +
    "<!--\n" +
    "%s\n" +
    "-->\n" +
    "===Referenced Protocols===\n" +
    "%s\n" +
    "===Notes===\n" +
    "%s\n" +
    "===QC Data===\n" +
    "%s\n" +
    "===Comments===\n" +
    "%s"

  attr_accessor :scraped_data, :protocols, :notes, :qcdata, :comments
  def initialize(existing_content=nil)
    parse_content(existing_content) if existing_content
  end

  def content
    format(TEMPLATE, @scraped_data, @protocols, @notes, @qcdata, @comments)
  end


  private
  def parse_content(content)
    re_str = Regexp.escape(TEMPLATE).gsub(/%s/, "(.*?)").gsub(/\\n/, "\\n+")
    regex = Regexp.new(re_str, Regexp::MULTILINE)
    (matched, @scraped_data, @protocols, @notes, @qcdata, @comments) = content.match(regex).to_a
    raise BadPageContentException.new("Unable to parse existing content") if matched.nil?
  end
end
