require 'rubygems'
require 'rsbundler'
require 'open-uri'
require 'mongrel'
require 'rar'
require 'digest'
require 'downloader'
require 'time'

$useragent = "RSProxy (0.0.2)"

server = Mongrel::HttpServer.new("127.0.0.1", "15685")

#$transfers = []

class RSProxyDownloader < Mongrel::HttpHandler
  def process(req,res)
    if req.params['REQUEST_URI'] =~ /^\/download\/(.+)$/
      bundleurl = "http://"+$1
      
      begin
        bundletext = open(bundleurl,"User-agent"=>$useragent).read
      rescue
        res.start(404) do |head,out|
          out.write("The bundle you requested does not exist.\n")
        end
        return
      end
      
      begin
        bundle = RSBundle.new(bundletext)
      rescue
        res.start(400) do |head,out|
          out.write("The file you asked for is not a bundle.\n")
        end
        return
      end
      
      # We can only cope with single files at the moment, so we take the first file in the bundle.
      urls = bundle.files[0].links
      
      dir = Digest::SHA1.hexdigest(urls.join("|"))

      if File.exists?("extract/#{dir}/.rsproxy")
        puts "Passing back #{bundle.name} // #{bundle.files[0].name}"
        details = open("extract/#{dir}/.rsproxy").read.split("\n")
        
        res.status = 200
        res.header["Content-Length"] = details[1]
        res.header["Content-Disposition"] = "inline; filename=#{details[0]}"
        res.send_status
        res.send_header
        open("./extract/#{dir}/#{details[0]}").each_char do |char|
          res.write char
        end
      else
        puts "Downloading #{bundle.name} // #{bundle.files[0].name}"

        FileUtils.mkdir_p("downloads/#{dir}/")

        details = nil
        extracted = 0
        downloads = []
        urls.each_with_index do |url,num|
          filename = url.gsub(/^.+\/(.+?)$/,"\\1")
          downloads.push(filename)
          puts "#{bundle.files[0].name} #{num + 1} / #{urls.length}"
          dest = "downloads/#{dir}/#{filename}"
          $dlr.start("#{bundle.name} [#{num + 1}/#{urls.length}]",url,dest,
          lambda{
            if details.nil?
              details = Rar.new(dest,bundle.files[0].password).files.sort {|y,x| x[1].to_i <=> y[1].to_i}[0]
              
              if details.nil?
                # You're probably over your daily limit, the file is dead or you're not logged in.
                raise "Not a valid rar."
              end
              
              res.status = 200
              res.header["Content-Length"] = details[1]
              res.header["Content-Disposition"] = "inline; filename=#{details[0]}"
              res.send_status
              res.send_header
            else
              newdata = Rar.new(dest,bundle.files[0].password).extract_file(details[0],extracted)
              extracted += newdata.length
              res.write newdata
            end
          })                  
        end

        Rar.new("downloads/#{dir}/#{downloads[0]}",bundle.files[0].password).extract("extract/#{dir}/")

        settings = open("extract/#{dir}/.rsproxy","w")
        details.push(bundleurl)
        details.push(Time.now.to_i)
        details.push(bundletext)
        settings.write(details.join("\n"))
        settings.close

        FileUtils.rm_r("downloads/#{dir}")
      end      
      return
    else
      res.start(400) do |head,out|
        out.write("You must specify a bundle. See <a href=\"/\">the root</a> for documentation.\n")
      end
    end
  end
end

class RSProxyAdmin < Mongrel::HttpHandler
  def process(req,res)
    res.start(200) do |head,out|
      out.write("Downloads\n---------\n")
      $dlr.running.each do |dl|
        out.write(((dl[:name].length > 50) ? dl[:name] : dl[:name][0..47]+"...").ljust(51," "))
        if dl[:size].nil?
          out.write "|"+(" -"*22)+" | --:--\n"
        else
          taken = (Time.new.to_i - dl[:started])
          left = dl[:size] - dl[:complete]
          av_speed = dl[:complete]/taken
          
          remaining = left / av_speed
          min = (remaining / 60).to_i.to_s.rjust(2,"0")
          sec = (remaining % 60).to_i.to_s.rjust(2,"0")
          done =  ((dl[:complete]*45) / dl[:size])
          out.write "|"+(">"*done)+("-"*(45-done))+"| #{min}:#{sec} @ "+(av_speed / 1024).to_s+"KBps\n"
        end
        out.write"\n"
      end
    end
  end
end

puts "Setting up the downloader..."
$dlr = Downloader.new

puts "Starting the Server..."
server.register("/",Mongrel::DirHandler.new("./docs/"))
server.register("/download/",RSProxyDownloader.new)
server.register("/info/",RSProxyAdmin.new)
server.run.join