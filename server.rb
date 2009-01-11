require 'rubygems'
require 'rsbundler'
require 'open-uri'
require 'webrick'
require 'plist'

server = WEBrick::HTTPServer.new(
  :Port => 15685,
  :DocumentRoot    => Dir::pwd + "/docs"
)

class RSProxyServer < WEBrick::HTTPServlet::AbstractServlet
  def initialize(server)
    @useragent = "RSProxy"
    
    if File.exists?("rapidshare.cookie")
      @cookie = open("rapidshare.cookie").read
    else
      Plist::parse_xml("/Users/jp/Library/Cookies/Cookies.plist").each do |hash|
        if hash['Domain'] =~ /rapidshare\.com$/
          @cookie = hash['Value']
          break
        end
      end
      open("rapidshare.cookie","w").print @cookie
    end
  end
  
  def do_GET(req,res)
    if req.unparsed_uri =~ /\/download\/(.+)/
      bundleurl = "http://"+$1
      
      begin
        bundletext = open(bundleurl,"User-agent"=>@useragent).read
      rescue
        res.body = "There was an error getting your bundle"
        return
      end
      
      begin
        bundle = RSBundle.new(bundletext)
      rescue
        res.body = "There was an error parsing your bundle"
        return
      end
      
      res.body = downloadbundle(bundle)
      return
    else
      # do 404
      res.body = "That bundle could not be found"
      return
    end
  end
    
  def downloadbundle(bundle)
    # We can only cope with single files at the moment, so we take the first file in the bundle.
    urls = bundle.files[0].links

    pw = (bundle.files[0].password.nil?) ? "" : " -p#{bundle.files[0].password}"

    puts "Downloading #{bundle.name} // #{bundle.files[0].name}"

    dir = bundle.files[0].name
    
    FileUtils.mkdir("downloads/#{dir}/")

    details = nil
    downloads = []
    urls.each do |url|
      filename = url.gsub(/^.+\/(.+?)$/,"\\1")
      downloads.push(filename)

      download = open("downloads/#{dir}/#{filename}","w")
      open(url,"Cookie"=>@cookie,"User-agent"=>@useragent).each_line { |line| 
        if details.nil? and download.pos > 4096
          files = `unrar l#{pw} "downloads/#{dir}/#{filename}"`.scan(/\n (.+?)\s+([0-9]+)\s+[0-9]+\s+/).to_a[0..-2]

          details = files.sort {|y,x| x[1].to_i <=> y[1].to_i}[0]
        end
        download.write line
      }
      download.close
    end

    #{}`unrar x#{pw} -y downloads/#{dir}/#{downloads[0]} extract/#{dir}/`

    #FileUtils.rm_r("downloads/#{dir}")
    p details
    while not File.exist?("extract/#{dir}/#{details[0]}")
      sleep 1
    end
    open("extract/#{dir}/#{details[0]}").read
  end

  
end

server.mount("/download/",RSProxyServer)

trap("INT"){ s.shutdown }
server.start