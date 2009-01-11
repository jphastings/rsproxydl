require 'rubygems'
require 'rsbundler'
require 'open-uri'
require 'mongrel'
require 'plist'
require 'rar'
require 'digest'
require 'uri'

server = Mongrel::HttpServer.new("127.0.0.1", "15685")

class RSProxyServer < Mongrel::HttpHandler
  def initialize
    @useragent = "RSProxy"
    
    if File.exists?("rapidshare.cookie")
      @cookie = open("rapidshare.cookie").read
    else
      # Need to make this work for other operating systems / users
      Plist::parse_xml("/Users/jp/Library/Cookies/Cookies.plist").each do |hash|
        if hash['Domain'] =~ /rapidshare\.com$/
          @cookie = "user="+hash['Value']
          break
        end
      end
      open("rapidshare.cookie","w").print @cookie
    end
  end
  
  def process(req,res)
    if req.params['REQUEST_URI'] =~ /\/download\/(.+)/
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
      
      dir = Digest::SHA1.hexdigest(bundle.files.join("|"))

      if File.exists?("extract/#{dir}/.rsproxy")
        details = open("extract/#{dir}/.rsproxy").read.split("\n")
        
        res.status = 200
        res.header["Content-Length"] = details[1]
        res.header["Content-Disposition"] = "inline; filename=#{details[0]}"
        res.send_status
        res.send_header
      else
        # We can only cope with single files at the moment, so we take the first file in the bundle.
        urls = bundle.files[0].links

        puts "Downloading #{bundle.name} // #{bundle.files[0].name}"

        FileUtils.mkdir_p("downloads/#{dir}/")

        details = nil
        downloads = []
        urls.each do |url|
          filename = url.gsub(/^.+\/(.+?)$/,"\\1")
          downloads.push(filename)

          puts `curl -q -b "#{@cookie}\" -A "#{@useragent}" -L -o "downloads/#{dir}/#{filename}" #{url}`

          if details.nil?
            files = Rar.new("downloads/#{dir}/#{filename}").files

            details = files.sort {|y,x| x[1].to_i <=> y[1].to_i}[0] if not files.empty?
            res.status = 200
            res.header["Content-Length"] = details[1]
            res.header["Content-Disposition"] = "inline; filename=#{details[0]}"
            res.send_status
            res.send_header
          end

          if details.nil?
            # You're probably over your daily limit, the file is dead or you're not logged in.
            raise "Not a valid rar."
          end
        end

        Rar.new("downloads/#{dir}/#{downloads[0]}",bundle.files[0].password).extract("extract/#{dir}/")

        settings = open("extract/#{dir}/.rsproxy","w")
        settings.write(details.join("\n"))
        settings.close

        FileUtils.rm_r("downloads/#{dir}")
      end
      res.write open("./extract/#{dir}/#{details[0]}").read
      
      return
    else
      # do 404
      res.body = "That bundle could not be found"
      return
    end
  end
  
end

server.register("/",Mongrel::DirHandler.new("./docs/"))
server.register("/download/",RSProxyServer.new)
server.register("/ready/",Mongrel::DirHandler.new("./extract/"))

server.run.join