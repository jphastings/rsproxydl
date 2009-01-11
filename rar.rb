class Rar
  def initialize(filename,password = nil)
    @password = password
    @filename = filename
  end
  
  def files
    `unrar l "#{@filename}"`.scan(/\n \*?(.+?)\s+([0-9]+)\s+[0-9]+\s+/).to_a[0..-2]
  end
  
  def extract(destinationdir = "")
    switch = pw
    `unrar x#{pw} -y #{@filename} #{destinationdir}`
  end
  
  private
  
  def pw
    (@password.nil?) ? "" : " -p#{@password}"
  end  
end