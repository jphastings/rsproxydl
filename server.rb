require 'rubygems'
require 'rsbundler'
require 'open-uri'
require 'webrick'
require 'plist'
require 'rar'

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
          @cookie = "user="+hash['Value']
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

    puts "Downloading #{bundle.name} // #{bundle.files[0].name}"

    dir = bundle.files[0].name
    
    FileUtils.mkdir_p("downloads/#{dir}/")

    details = nil
    downloads = []
    urls.each do |url|
      filename = url.gsub(/^.+\/(.+?)$/,"\\1")
      downloads.push(filename)

      download = open("downloads/#{dir}/#{filename}","w")
      open(url,"Cookie"=>@cookie,"User-agent"=>@useragent).each_char { |chunk| 
        if details.nil? and download.pos > 1024
          files = `unrar l#{pw} "downloads/#{dir}/#{filename}"`.scan(/\n\s*\*?(.+?)\s+([0-9]+)\s+[0-9]+\s+/).to_a[0..-2]
          details = files.sort {|y,x| x[1].to_i <=> y[1].to_i}[0] if not files.empty?
          res.header['Content-length'] = details[1]
        end
        download.write chunk
      }
      download.close
      
      # Final attempt
      if details.nil?
        files = Rar.new("downloads/#{dir}/#{filename}").files

        details = files.sort {|y,x| x[1].to_i <=> y[1].to_i}[0] if not files.empty?
      end
      
      if details.nil?
        # You're probably over your daily limit, the file is dead or you're not logged in.
        raise "Not a valid rar."
      end
      
    end

    Rar.new("downloads/#{dir}/#{downloads[0]}",bundle.files[0].password).extract("extract/#{dir}")

    FileUtils.rm_r("downloads/#{dir}")
    if not File.exist?("extract/#{dir}/#{details[0]}")
      raise "The file we expect to be there has gone!"
    end
    open("extract/#{dir}/#{details[0]}").read
  end

  
end

server.mount("/download/",RSProxyServer)

trap("INT"){ s.shutdown }
server.start