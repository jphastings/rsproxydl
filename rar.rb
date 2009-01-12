class Rar
  def initialize(filename,password = nil)
    if not File.exists?(filename)
      raise "That rar doesn't exist"
    end
    @password = password
    @filename = filename
  end
  
  def files
    pw = (@password.nil?) ? "-" : "\"#{@password}\""
    `unrar l -p#{pw} "#{@filename}"`.scan(/\n\s*\*?(.+?)\s+([0-9]+)\s+[0-9]+\s+/).to_a[0..-2]
  end
  
  def extract(destinationdir = "")
    pw = (@password.nil?) ? "-" : "\"#{@password}\""
    `unrar x -p#{pw} -y #{@filename} #{destinationdir}/`
  end
  
end