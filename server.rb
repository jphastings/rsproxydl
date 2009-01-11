require 'rubygems'
require 'rsbundler'
require 'open-uri'
require 'mongrel'
require 'rar'
require 'digest'
require 'downloader'

$useragent = "RSProxy (0.0.1)"

server = Mongrel::HttpServer.new("127.0.0.1", "15685")

class RSProxyDownloader < Mongrel::HttpHandler
  def process(req,res)
    if req.params['REQUEST_URI'] =~ /\/download\/(.+)/
      bundleurl = "http://"+$1
      
      begin
        bundletext = open(bundleurl,"User-agent"=>$useragent).read
      rescue
        # 404 not found
        # Bundle is not there
        return
      end
      
      begin
        bundle = RSBundle.new(bundletext)
      rescue
        # invalid request
        # Bundle is not valid
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
        urls.each_with_index do |url,num|
          filename = url.gsub(/^.+\/(.+?)$/,"\\1")
          downloads.push(filename)
          
          if num == 0
            $dlr.start("#{bundle.name} [#{num + 1}/#{urls.length}]",url,"downloads/#{dir}/#{filename}",lambda{|got_details|
              details = got_details
              res.status = 200
              res.header["Content-Length"] = details[1]
              res.header["Content-Disposition"] = "inline; filename=#{details[0]}"
              res.send_status
              res.send_header
            })
            if details.nil?
              # You're probably over your daily limit, the file is dead or you're not logged in.
              raise "Not a valid rar."
            end
          else
            $dlr.start("#{bundle.name} [#{num + 1}/#{urls.length}]",url,"downloads/#{dir}/#{filename}")
          end          
        end

        Rar.new("downloads/#{dir}/#{downloads[0]}",bundle.files[0].password).extract("extract/#{dir}/")

        settings = open("extract/#{dir}/.rsproxy","w")
        details.push(bundleurl)
        details.push(bundletext)
        settings.write(details.join("\n"))
        settings.close

        FileUtils.rm_r("downloads/#{dir}")
      end
      res.write open("./extract/#{dir}/#{details[0]}").read
      
      return
    end
  else
    # Malformed Request (no bundle url given)
  end
  
end

puts "Setting up the downloader..."
$dlr = Downloader.new

puts "Starting the Server..."
server.register("/",Mongrel::DirHandler.new("./docs/"))
server.register("/download/",RSProxyDownloader.new)
server.run.join